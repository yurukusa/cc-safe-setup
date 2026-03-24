CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "class.*extends.*Component|function.*\(\)" && echo "$CONTENT" | grep -q "render" && ! echo "$CONTENT" | grep -q "ErrorBoundary" && echo "NOTE: Consider adding ErrorBoundary" >&2
exit 0
