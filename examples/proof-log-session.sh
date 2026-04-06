#!/bin/bash
# proof-log-session.sh — Generate session summary on Stop event
#
# Solves: "What did the AI do last week?" — activity logs exist but are unreadable
# Creates a human-readable 5W1H summary from the activity log at session end.
#
# Usage: Add to settings.json as a Stop hook
#
# {
#   "hooks": {
#     "Stop": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/proof-log-session.sh" }]
#     }]
#   }
# }
#
# Output: ~/ops/proof-log/YYYY-MM-DD.md (appended)
# Requires: activity-logger.sh to be running as a PostToolUse hook

set -u

LOG_FILE="${HOME}/.claude/activity-log.jsonl"
DATE=$(date +"%Y-%m-%d")
PROOF_DIR="${HOME}/ops/proof-log"
PROOF_FILE="${PROOF_DIR}/${DATE}.md"

mkdir -p "$PROOF_DIR"

[ ! -f "$LOG_FILE" ] && exit 0

# Count today's activity
TODAY_START=$(date -u -d "today 00:00:00" +"%Y-%m-%dT" 2>/dev/null || date -u +"%Y-%m-%dT")
EDIT_COUNT=$(grep -c '"tool":"Edit"' "$LOG_FILE" 2>/dev/null) || EDIT_COUNT=0
WRITE_COUNT=$(grep -c '"tool":"Write"' "$LOG_FILE" 2>/dev/null) || WRITE_COUNT=0
BASH_COUNT=$(grep -c '"tool":"Bash"' "$LOG_FILE" 2>/dev/null) || BASH_COUNT=0
READ_COUNT=$(grep -c '"tool":"Read"' "$LOG_FILE" 2>/dev/null) || READ_COUNT=0
ERROR_COUNT=$(grep -c '"error_pattern":"[^"]*[a-zA-Z]' "$LOG_FILE" 2>/dev/null) || ERROR_COUNT=0

# Get edited files
FILES=$(grep '"tool":"Edit\|Write"' "$LOG_FILE" 2>/dev/null | jq -r '.file // empty' 2>/dev/null | sort -u | head -10)

{
  echo ""
  echo "## Session $(date +"%H:%M")"
  echo "- Edit: ${EDIT_COUNT}, Write: ${WRITE_COUNT}, Bash: ${BASH_COUNT}, Read: ${READ_COUNT}"
  [ "$ERROR_COUNT" -gt 0 ] && echo "- Errors detected: ${ERROR_COUNT}"
  if [ -n "$FILES" ]; then
    echo "- Files touched:"
    echo "$FILES" | while read -r f; do
      [ -n "$f" ] && echo "  - $f"
    done
  fi
} >> "$PROOF_FILE"

# Rotate activity log (keep last 1000 lines)
LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null) || LINE_COUNT=0
if [ "$LINE_COUNT" -gt 1000 ]; then
  tail -1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

exit 0
