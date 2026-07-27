#!/bin/bash
# ================================================================
# agent-view-quota-decrement.sh — Decrement Task counter on completion
# ================================================================
# PURPOSE:
#   Companion to agent-view-quota-warn.sh. Decrements the concurrent-
#   Task counter when a Task tool returns, so the warn-side counter
#   accurately reflects currently-running parallel agents.
#
# TRIGGER: PostToolUse
# MATCHER: "Task"
# ================================================================

set -uo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Task" ] || exit 0

SESSION_KEY="${CLAUDE_CODE_SESSION_ID:-ppid-${PPID:-unknown}}"
COUNTER_FILE="/tmp/cc-agent-view-tasks-${SESSION_KEY}"

# Decrement (clamp at 0)
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
case "$COUNT" in
    ''|*[!0-9]*) COUNT=0 ;;
esac
COUNT=$((COUNT - 1))
[ "$COUNT" -lt 0 ] && COUNT=0
echo "$COUNT" > "$COUNTER_FILE"

exit 0
