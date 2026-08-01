#!/bin/bash
# iteration-quality-degradation-detector.sh — Warn when the same file is being edited repeatedly across turns
#
# Solves: anthropics/claude-code#61989 — Codex (GPT-5.5) reviews Opus 4.7's code,
#   each fix cycle produces new errors instead of converging. A simple shell script
#   (193 lines) accumulates errors across review cycles instead of stabilizing.
#
# Structural observation: when the model is competent in a single turn but the
# multi-turn fix loop diverges, the surface marker is *the same file being edited
# repeatedly within a short window*. The hook does not judge code quality (it
# can't); it surfaces the iteration pattern so the operator can interrupt before
# more cycles accumulate.
#
# How it works:
#   PostToolUse hook on Edit/Write/MultiEdit appends a receipt to per-session state.
#   UserPromptSubmit hook reads recent receipts (default: last 30 minutes), counts
#   per-file edits, and emits an advisory if any file exceeds the threshold
#   (default: 3 edits in the window).
#
# This is the Cluster-1 hook from the 2026-05-25 customer pain audit
# (~/ops/customer-pain-audit-2026-05-25-post-launch-cluster.md). Cluster 1 names
# the iteration-cycle quality degradation pattern that is new in the May 2026
# issue corpus and not covered by existing cc-safe-setup hooks.
#
# TRIGGER: PostToolUse + UserPromptSubmit
# MATCHER: "Edit|Write|MultiEdit" for PostToolUse, "" for UserPromptSubmit
#
# Usage (settings.json):
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Edit|Write|MultiEdit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/iteration-quality-degradation-detector.sh" }]
#     }],
#     "UserPromptSubmit": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/iteration-quality-degradation-detector.sh" }]
#     }]
#   }
# }
#
# Configuration:
#   CC_ITERATION_DETECTOR_DISABLE=1 — skip entirely
#   CC_ITERATION_DETECTOR_THRESHOLD=3 — edits per file before advisory fires (default 3)
#   CC_ITERATION_DETECTOR_WINDOW_SEC=1800 — time window in seconds (default 30 min)
#   CC_ITERATION_DETECTOR_STATE_DIR=~/.claude/state/iteration-degradation
#   CC_ITERATION_DETECTOR_MODE=strict — exit 2 on UserPromptSubmit (default advisory exits 0)

# Read stdin first to avoid EPIPE on disable
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-iteration-quality-degradation-detector-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [iteration-quality-degradation-detector]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat 2>/dev/null || true)

[ "${CC_ITERATION_DETECTOR_DISABLE:-0}" = "1" ] && exit 0
[ -z "$INPUT" ] && exit 0

THRESHOLD="${CC_ITERATION_DETECTOR_THRESHOLD:-3}"
WINDOW_SEC="${CC_ITERATION_DETECTOR_WINDOW_SEC:-1800}"
STATE_DIR_BASE="${CC_ITERATION_DETECTOR_STATE_DIR:-$HOME/.claude/state/iteration-degradation}"

# Determine event
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
HAS_TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r 'has("tool_response")' 2>/dev/null)
HAS_PROMPT=$(printf '%s' "$INPUT" | jq -r 'has("prompt") or has("user_prompt") or has("submitted_prompt")' 2>/dev/null)

if [ -z "$EVENT" ]; then
    if [ "$HAS_TOOL_RESPONSE" = "true" ]; then
        EVENT="PostToolUse"
    elif [ "$HAS_PROMPT" = "true" ]; then
        EVENT="UserPromptSubmit"
    else
        exit 0
    fi
fi

# Sanitize session ID for filesystem use
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // .session // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_' | head -c 64)

SESSION_DIR="$STATE_DIR_BASE/$SESSION_ID"
mkdir -p "$SESSION_DIR" 2>/dev/null || true
LOG_FILE="$SESSION_DIR/edits.log"

if [ "$EVENT" = "PostToolUse" ]; then
    # Only track Edit/Write/MultiEdit
    case "$TOOL_NAME" in
        Edit|Write|MultiEdit) ;;
        *) exit 0 ;;
    esac

    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0

    TS=$(date +%s)
    # Append: timestamp<TAB>file_path (file_path may contain spaces but no tabs typically)
    printf '%s\t%s\n' "$TS" "$FILE_PATH" >> "$LOG_FILE" 2>/dev/null

    # Prune old entries to keep the log bounded (older than 24 hours)
    if [ -f "$LOG_FILE" ]; then
        CUTOFF=$((TS - 86400))
        awk -F'\t' -v cut="$CUTOFF" '$1 >= cut { print }' "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
    fi
    exit 0
fi

if [ "$EVENT" = "UserPromptSubmit" ]; then
    [ ! -f "$LOG_FILE" ] && exit 0

    NOW=$(date +%s)
    CUTOFF=$((NOW - WINDOW_SEC))

    # Count edits per file within the window
    HOT_FILES=$(awk -F'\t' -v cut="$CUTOFF" -v thr="$THRESHOLD" '
        $1 >= cut { count[$2]++ }
        END {
            for (f in count) {
                if (count[f] >= thr) {
                    printf "%d\t%s\n", count[f], f
                }
            }
        }
    ' "$LOG_FILE" 2>/dev/null | sort -rn | head -5)

    [ -z "$HOT_FILES" ] && exit 0

    # Format minutes for human readability
    HUMAN_WINDOW=$((WINDOW_SEC / 60))

    cat >&2 <<EOF
<system-reminder>
iteration-quality-degradation-detector observed repeated edits to the same file(s) within the last ${HUMAN_WINDOW} minutes.

Files at or above the threshold (${THRESHOLD} edits):
$(printf '%s' "$HOT_FILES" | awk -F'\t' '{ printf "  %s edits: %s\n", $1, $2 }')

This pattern matches the iteration-cycle quality degradation reported in
anthropics/claude-code#61989: each fix cycle produces new errors instead of
converging. If you are in a multi-turn fix loop with a cross-model reviewer
(Codex reviewing Opus, or similar), consider interrupting:

  - Stop, read the full file once, and ask "what is the root cause?"
  - Revert to a known-good commit and re-approach with a single-pass strategy
  - Switch reviewer model (different model may have different blind spots)
  - Clear the iteration counter: rm -f ${LOG_FILE}

Configuration: CC_ITERATION_DETECTOR_THRESHOLD=N (default 3),
CC_ITERATION_DETECTOR_WINDOW_SEC=N (default 1800).
</system-reminder>
EOF

    # Strict mode blocks; default advisory exits 0
    if [ "${CC_ITERATION_DETECTOR_MODE:-advisory}" = "strict" ]; then
        exit 2
    fi
    exit 0
fi

exit 0
