#!/bin/bash
# dispatch-liveness-watchdog.sh — Surface in-flight sub-agent dispatches that
# have been running longer than a configurable threshold, so operators see
# the hang before they have to kill the session at the OS level.
#
# Solves: #61405 ("Subagent delegation lacks timeout, monitoring, and abort
# controls — caused 12+ hour session hang"). The harness has no built-in
# timeout primitive for Agent-tool dispatches; this hook is the operator-
# side proxy that surfaces the hang at the next UserPromptSubmit so the
# operator has a visible signal rather than having to notice that nothing
# is happening.
#
# This is *symptom surfacing*, not root cause fixing. The full repair (a
# real timeout / abort primitive in the harness) has to land at the Agent-
# tool layer. The hook just makes the symptom observable at a point the
# operator already looks (the next prompt they type).
#
# Architecture:
#   * PreToolUse  + matcher "Agent": writes a per-dispatch state file under
#     ~/.claude/state/dispatch-watchdog/<session>/<unix-timestamp>-<rand>.
#   * PostToolUse + matcher "Agent": removes the OLDEST state file in the
#     session's directory (FIFO assumption — dispatches that complete in
#     order have their state files retired in order; out-of-order completion
#     simply causes the wrong file to be retired but the in-flight count
#     stays accurate, which is what the advisory cares about).
#   * UserPromptSubmit: lists state files older than the threshold and
#     emits an advisory naming each (with elapsed wall-clock) so the
#     operator sees the hang.
#
# Companion to:
#   * #61102's PR #281 scope-expansion-receipt.sh (sub-pattern 4 defense)
#   * #61315's PR #286 dispatch-allowlist-preflight.sh (sub-pattern 2 prevention)
#   * #61107's PR #275 route-handler-body-emptiness-gate.sh (sub-pattern 1 defense)
#
# This hook addresses sub-pattern 3 (absence of observation and control) in
# the four-sub-pattern decomposition documented at
# https://gist.github.com/yurukusa/9857a9ed407696ba8483b354917ff161
#
# TRIGGER: PreToolUse, PostToolUse, UserPromptSubmit
# MATCHER (for the two ToolUse events): "Agent"
#
# CONFIGURATION (environment variables):
#   CC_DISPATCH_WATCHDOG_THRESHOLD_SEC   default 1800 (30 minutes)
#   CC_DISPATCH_WATCHDOG_STATE_DIR       default ~/.claude/state/dispatch-watchdog
#   CC_DISPATCH_WATCHDOG_DISABLE         "1" → skip entirely
#   CC_DISPATCH_WATCHDOG_MODE            "strict" → exit 2 when stale
#                                        dispatches are present (default:
#                                        advisory / exit 0)
#
# USAGE (settings.json — three registrations of the same hook):
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Agent",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/dispatch-liveness-watchdog.sh" }]
#       }],
#       "PostToolUse": [{
#         "matcher": "Agent",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/dispatch-liveness-watchdog.sh" }]
#       }],
#       "UserPromptSubmit": [{
#         "matcher": "",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/dispatch-liveness-watchdog.sh" }]
#       }]
#     }
#   }

set -uo pipefail

# Read stdin first so the upstream writer never sees EPIPE/141, even when the
# watchdog is disabled.
INPUT=$(cat 2>/dev/null || true)

[ "${CC_DISPATCH_WATCHDOG_DISABLE:-0}" = "1" ] && exit 0
[ -z "$INPUT" ] && exit 0

# Identify which event we are servicing. Claude Code's hook input includes
# hook_event_name in newer versions; we infer when it's not present.
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
HAS_TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r 'has("tool_response")' 2>/dev/null)
HAS_TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r 'has("tool_input")' 2>/dev/null)
HAS_PROMPT=$(printf '%s' "$INPUT" | jq -r 'has("prompt") or has("user_prompt") or has("submitted_prompt")' 2>/dev/null)

if [ -z "$EVENT" ]; then
    if [ "$HAS_TOOL_RESPONSE" = "true" ]; then
        EVENT="PostToolUse"
    elif [ "$HAS_TOOL_INPUT" = "true" ]; then
        EVENT="PreToolUse"
    elif [ "$HAS_PROMPT" = "true" ]; then
        EVENT="UserPromptSubmit"
    else
        exit 0
    fi
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // .session // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
# Sanitize session id for filesystem use (alnum + dash + underscore only).
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_' | head -c 64)

STATE_ROOT="${CC_DISPATCH_WATCHDOG_STATE_DIR:-$HOME/.claude/state/dispatch-watchdog}"
SESSION_DIR="$STATE_ROOT/$SESSION_ID"
THRESHOLD="${CC_DISPATCH_WATCHDOG_THRESHOLD_SEC:-1800}"

mkdir -p "$SESSION_DIR" 2>/dev/null || exit 0

case "$EVENT" in
    PreToolUse)
        # Only track Agent dispatches.
        if [ "$TOOL_NAME" != "Agent" ]; then
            exit 0
        fi
        TS=$(date +%s)
        # 6-byte random to disambiguate concurrent dispatches at the same second.
        RAND=$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || echo "0000")
        STATE_FILE="$SESSION_DIR/${TS}-${RAND}"
        # Capture a short summary of the dispatch for the advisory.
        SUMMARY=$(printf '%s' "$INPUT" | jq -r '
            (.tool_input.subagent_type // "")
            + " | "
            + ((.tool_input.description // .tool_input.prompt // "")[0:120] | gsub("\n"; " "))
        ' 2>/dev/null)
        printf '%s\n' "${SUMMARY:-(no summary)}" > "$STATE_FILE" 2>/dev/null
        exit 0
        ;;
    PostToolUse)
        if [ "$TOOL_NAME" != "Agent" ]; then
            exit 0
        fi
        # Remove the oldest state file for this session. FIFO assumption;
        # see header comment.
        OLDEST=$(ls -1tr "$SESSION_DIR" 2>/dev/null | head -1)
        if [ -n "$OLDEST" ]; then
            rm -f "$SESSION_DIR/$OLDEST" 2>/dev/null
        fi
        exit 0
        ;;
    UserPromptSubmit)
        NOW=$(date +%s)
        STALE_COUNT=0
        # Build a list of stale dispatches.
        STALE_LINES=""
        if [ -d "$SESSION_DIR" ]; then
            for f in "$SESSION_DIR"/*; do
                [ -f "$f" ] || continue
                BASENAME=$(basename "$f")
                START_TS=${BASENAME%%-*}
                # Skip if filename is not parseable as a timestamp.
                case "$START_TS" in
                    ''|*[!0-9]*) continue ;;
                esac
                ELAPSED=$((NOW - START_TS))
                if [ "$ELAPSED" -ge "$THRESHOLD" ]; then
                    STALE_COUNT=$((STALE_COUNT + 1))
                    SUMMARY=$(head -c 200 "$f" 2>/dev/null | head -1)
                    HUMAN_ELAPSED=$(printf '%dm %ds' $((ELAPSED / 60)) $((ELAPSED % 60)))
                    STALE_LINES="${STALE_LINES}  - started ${HUMAN_ELAPSED} ago: ${SUMMARY:-(no summary)}"$'\n'
                fi
            done
        fi

        if [ "$STALE_COUNT" -eq 0 ]; then
            exit 0
        fi

        HUMAN_THRESHOLD=$(printf '%dm' $((THRESHOLD / 60)))
        {
            echo "<system-reminder>"
            echo "STALE SUB-AGENT DISPATCH(ES) — ${STALE_COUNT} Agent-tool dispatch(es)"
            echo "have been running longer than the watchdog threshold (${HUMAN_THRESHOLD})"
            echo "without a corresponding PostToolUse signal:"
            echo ""
            printf '%s' "$STALE_LINES"
            echo ""
            echo "Sub-agent dispatches in Claude Code have no built-in timeout, monitoring,"
            echo "or abort affordance (anthropics/claude-code#61405). The harness will wait"
            echo "indefinitely for the dispatch to return; a hung dispatch will block the"
            echo "session until the operator force-kills it at the OS level."
            echo ""
            echo "Operator-side options:"
            echo "  1. Wait, if the dispatch is plausibly still progressing."
            echo "  2. Identify the OS-level process (\`ps\` / Task Manager) and SIGKILL it."
            echo "     Note: this will lose in-flight state in the parent session too."
            echo "  3. Adjust CC_DISPATCH_WATCHDOG_THRESHOLD_SEC if your normal dispatches"
            echo "     legitimately run longer than ${HUMAN_THRESHOLD}."
            echo ""
            echo "To clear the watchdog state (after force-killing a hung dispatch):"
            echo "  rm -f ${SESSION_DIR}/*"
            echo ""
            echo "To disable this watchdog entirely, set"
            echo "CC_DISPATCH_WATCHDOG_DISABLE=1 in your environment."
            echo "</system-reminder>"
        } >&2

        if [ "${CC_DISPATCH_WATCHDOG_MODE:-advisory}" = "strict" ]; then
            exit 2
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
