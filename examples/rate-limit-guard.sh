INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
STATE="/tmp/cc-rate-limit-$(echo "$PWD" | md5sum | cut -c1-8)"
NOW=$(date +%s)
if [ -f "$STATE" ]; then
  LAST=$(cat "$STATE")
  DIFF=$((NOW - LAST))
  if [ "$DIFF" -lt 1 ]; then
    echo "WARNING: Rapid tool calls (${DIFF}s apart). Slow down." >&2
  fi
fi
echo "$NOW" > "$STATE"
exit 0
