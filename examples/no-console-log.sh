INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
case "$FILE" in *.test.*|*.spec.*|*debug*) exit 0 ;; esac
if echo "$CONTENT" | grep -qE '\bconsole\.(log|debug)\b'; then
  echo "WARNING: console.log detected in $FILE. Use proper logging." >&2
fi
exit 0
