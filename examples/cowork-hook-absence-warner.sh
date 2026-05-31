#!/bin/bash
# ================================================================
# cowork-hook-absence-warner.sh — Warn CLI operators with a non-trivial
#                                 ~/.claude/settings.json hook stack
#                                 that the Cowork sandbox silently
#                                 drops every one of those hooks
# ================================================================
# PURPOSE:
#   Cluster 11 sub-pattern 11E (Hook surface absence) documents that
#   the Cowork sandbox does not fire any hook defined in
#   ~/.claude/settings.json. The operator-side defense surface that
#   14-day-active 1,582+ cc-safe-setup users rely on (UserPromptSubmit,
#   Stop, PostToolUse, PreToolUse, SessionStart) is silently inert
#   once the operator switches to a Cowork session.
#
#   Cluster 11 axis 11E issues:
#     #63360 — Cowork: Support Claude Code hooks (~/.claude/settings.json
#              — UserPromptSubmit, Stop, etc.) — feature request, 2026-05-28
#     #63047 — Plugin PostToolUse hooks still silently skip in Claude
#              Desktop / Cowork (re-filing closed #51904) — re-filing
#              with 7+ weeks of additional evidence, 2026-05-28
#     #51904 — original report, auto-closed for inactivity
#     #51281 — April 2026, French — auto-closed
#     #27398 — February 2026 — auto-closed as duplicate
#
#   The operator who installed a serious hook stack on the CLI surface
#   for cluster-1-19 defense will, on switching to Cowork, lose all of
#   that defense without any visible signal. This hook runs at
#   SessionStart on the CLI side, reads the operator's hook stack from
#   ~/.claude/settings.json, and — when the stack is non-trivial — once
#   per calendar day surfaces a stderr advisory: "your N hooks do not
#   fire in Cowork; here are the three operator-side workarounds."
#
#   The hook does NOT block. The advisory is a one-shot per calendar
#   day so multi-session-per-day operators are not nagged repeatedly.
#
# TRIGGER: SessionStart
# MATCHER: ""
# EXIT:    0 (always; advisory only)
#
# SETUP:
#   {
#     "hooks": {
#       "SessionStart": [
#         { "matcher": "",
#           "hooks": [
#             { "type": "command",
#               "command": "bash ~/path/to/cowork-hook-absence-warner.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }
#
# CONFIGURATION:
#   CC_COWORK_WARNER_DISABLE=1     — silence the hook entirely
#   CC_COWORK_WARNER_STATE_DIR=PATH — override state dir
#                                     (default $HOME/.claude)
#   CC_COWORK_WARNER_DATE=YYYY-MM-DD — date override (tests only)
#   CC_COWORK_WARNER_SETTINGS=PATH — settings file path override
#                                    (default $HOME/.claude/settings.json)
#   CC_COWORK_WARNER_MIN_HOOKS=N  — min hook count to trigger advisory
#                                   (default 1)
#
# RELATED CLUSTER 11 SHIPPED TOOLS:
#   - cowork-claudemd-helper.sh    (standalone, addresses 11A #62859)
#   - cowork-claude-md-load-checker.sh (CLI-side, addresses 11A #62859)
#   - cowork-fuse-staleness-watcher.sh (CLI-side, addresses 11A #62932)
#   - cowork-model-picker-advisor.sh (CLI-side, addresses 11C #62949)
#
# WHAT THIS HOOK ADDS:
#   The four shipped tools above address 11A and 11C. 11E (hook
#   surface absence) was not covered until this hook. The defense
#   surface for 11E is "warn the operator who has the most to lose"
#   — the operator whose CLI hook stack carries real defense value.
# ================================================================

set -uo pipefail

[ "${CC_COWORK_WARNER_DISABLE:-0}" = "1" ] && exit 0

SETTINGS="${CC_COWORK_WARNER_SETTINGS:-${HOME}/.claude/settings.json}"
STATE_DIR="${CC_COWORK_WARNER_STATE_DIR:-${HOME}/.claude}"
MIN_HOOKS="${CC_COWORK_WARNER_MIN_HOOKS:-1}"

# If no settings file, the operator has no hook stack to lose.
[ ! -f "$SETTINGS" ] && exit 0

# Count hooks across all event types. We count the leaf commands, not
# the matcher entries, so {"Stop":[{"matcher":"","hooks":[a,b,c]}]}
# correctly reports 3 hooks (not 1 matcher).
HOOK_COUNT=$(jq -r '
    (.hooks // {})
    | [.SessionStart, .UserPromptSubmit, .Stop, .PreToolUse, .PostToolUse, .PreCompact, .Notification]
    | map(. // [])
    | map([.[]? | .hooks // [] | .[]?] | length)
    | add
' "$SETTINGS" 2>/dev/null)

# If jq failed or returned non-numeric, exit silently.
case "$HOOK_COUNT" in
    ''|*[!0-9]*) exit 0 ;;
esac

# Below the threshold → not worth warning about.
[ "$HOOK_COUNT" -lt "$MIN_HOOKS" ] && exit 0

# One-shot per calendar day.
TODAY="${CC_COWORK_WARNER_DATE:-}"
if [ -z "$TODAY" ]; then
    TODAY=$(date '+%Y-%m-%d' 2>/dev/null) || exit 0
fi

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
STATE_FILE="$STATE_DIR/cowork-hook-absence-warner.last"

if [ -f "$STATE_FILE" ]; then
    LAST_DATE=$(head -1 "$STATE_FILE" 2>/dev/null)
    if [ "$LAST_DATE" = "$TODAY" ]; then
        exit 0
    fi
fi

# Stamp the state file BEFORE emitting (crash-mid-emit doesn't re-fire).
printf '%s\n' "$TODAY" > "$STATE_FILE" 2>/dev/null || true

cat >&2 <<EOF

[cowork-hook-absence-warner] NOTE: your ${HOOK_COUNT} CLI hooks do not
fire in the Cowork sandbox.

Cluster 11 sub-pattern 11E (Hook surface absence) — issues #63360 and
#63047 (re-filing of #51904) — documents that Cowork's GUI sandbox is
a different distribution surface than the CLI or Desktop, and
~/.claude/settings.json hooks are silently inert in it. Your
${HOOK_COUNT} configured hooks (across SessionStart, UserPromptSubmit,
Stop, PreToolUse, PostToolUse, PreCompact, Notification) will not
provide defense when you switch to a Cowork session.

Three operator-side workarounds:

  1. **Delay Cowork adoption for hook-dependent workflows.** If your
     hook stack carries real defense value (cluster-1/9/13/19 type
     coverage), continue using the CLI for that work until upstream
     #63360 lands.

  2. **Manual execution at Cowork boundaries.** For each hook your
     CLI workflow relies on, document the manual equivalent you'll
     run before and after a Cowork session (the cowork-claudemd-helper
     standalone script is the model for this — manual replication of
     what the SessionStart hook would have done).

  3. **CLI-only for sensitive operations.** Restrict Cowork to
     low-defense-value tasks (read-only exploration, documentation
     review, etc.) and keep code execution / destructive ops / cost-
     sensitive work in the CLI where your hooks apply.

This reminder fires once per calendar day. To silence it:
  export CC_COWORK_WARNER_DISABLE=1

Tracked at https://github.com/yurukusa/cc-safe-setup/blob/main/docs/cluster-tracker.html
(Cluster 11, sub-pattern 11E).

EOF

exit 0
