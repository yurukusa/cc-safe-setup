#!/bin/bash
# api-rate-limit-tracker.sh — Track API call frequency and warn on burst
#
# Prevents: Rate limit errors from rapid API calls.
#           Claude sometimes runs curl/fetch in tight loops.
#
# Tracks: API calls per minute via a log file.
# Warns at: 10 calls/min, blocks at 30 calls/min.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/api-rate-limit-tracker.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only track API-calling commands
echo "$COMMAND" | grep -qiE '(curl|wget|http|fetch)\s' || exit 0

LOG="/tmp/cc-api-rate-$$"
NOW=$(date +%s)

# Append timestamp
echo "$NOW" >> "$LOG"

# Count calls in the last 60 seconds
CUTOFF=$((NOW - 60))
RECENT=$(awk -v cutoff="$CUTOFF" '$1 >= cutoff' "$LOG" 2>/dev/null | wc -l)

if [ "$RECENT" -ge 30 ]; then
  echo "BLOCKED: $RECENT API calls in the last minute. Rate limit risk." >&2
  echo "  Add delays between calls or batch requests." >&2
  exit 2
elif [ "$RECENT" -ge 10 ]; then
  echo "WARNING: $RECENT API calls in the last minute. Slow down." >&2
fi

# Cleanup old entries
awk -v cutoff="$CUTOFF" '$1 >= cutoff' "$LOG" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "$LOG"

exit 0
