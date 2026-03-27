#!/bin/bash
# session-quota-tracker.sh — Track cumulative tool calls per session
#
# Solves: Token consumption spiraling without warning (#23706, #38335)
#         Users hit Max plan limits unexpectedly. This hook tracks
#         tool call count per session and warns at thresholds.
#
# Tracks: cumulative tool calls in a session file
# Warns at: 50, 100, 200, 500 tool calls
#
# TRIGGER: PostToolUse
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-quota-tracker.sh" }]
#     }]
#   }
# }

# Session tracking file
SESSION_FILE="/tmp/cc-quota-tracker-$$"

# Increment counter
if [ -f "$SESSION_FILE" ]; then
  COUNT=$(cat "$SESSION_FILE")
  COUNT=$((COUNT + 1))
else
  COUNT=1
fi
echo "$COUNT" > "$SESSION_FILE"

# Warn at thresholds
case "$COUNT" in
  50)  echo "[Session: 50 tool calls. Consider saving work.]" >&2 ;;
  100) echo "[Session: 100 tool calls. Token usage may be high.]" >&2 ;;
  200) echo "[Session: 200 tool calls. Check your usage dashboard.]" >&2 ;;
  500) echo "[Session: 500 tool calls. Consider starting a new session.]" >&2 ;;
esac

exit 0
