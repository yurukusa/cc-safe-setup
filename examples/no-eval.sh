#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
if echo "$CONTENT" | grep -qE '\beval\s*\('; then
  echo "WARNING: eval() detected in $FILE. Avoid eval for security." >&2
fi
exit 0
