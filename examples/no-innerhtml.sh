CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "\.innerHTML\s*=" && echo "WARNING: innerHTML XSS risk" >&2
exit 0
