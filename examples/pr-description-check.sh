INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bgh\s+pr\s+create\b'; then
  if ! echo "$COMMAND" | grep -qE '\-\-body|\-b\s'; then
    echo "WARNING: PR created without --body description." >&2
  fi
fi
exit 0
