#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
LEN=${#CONTENT}
MAX="${CC_MAX_FILE_SIZE:-1048576}"
if [ "$LEN" -gt "$MAX" ]; then
  echo "BLOCKED: File content is ${LEN} bytes (limit: ${MAX})." >&2
  exit 2
fi
exit 0
