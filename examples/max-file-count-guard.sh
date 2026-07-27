#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
STATE="/tmp/cc-new-files-count"
echo "$FILE" >> "$STATE"
COUNT=$(wc -l < "$STATE" 2>/dev/null || echo 0)
[ "$COUNT" -ge 20 ] && echo "WARNING: $COUNT new files created this session." >&2
exit 0
