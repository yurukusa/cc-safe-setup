CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "it\(['\"](test|check|should)\s" && echo "NOTE: Non-descriptive test name" >&2
exit 0
