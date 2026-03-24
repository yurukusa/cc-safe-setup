#!/bin/bash
# max-line-length-check.sh — Warn on lines exceeding max length after edit
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0
MAX="${CC_MAX_LINE_LENGTH:-120}"
LONG=$(awk -v max="$MAX" 'length > max {count++} END {print count+0}' "$FILE" 2>/dev/null)
[ "$LONG" -gt 0 ] && echo "NOTE: $FILE has $LONG lines exceeding $MAX characters." >&2
exit 0
