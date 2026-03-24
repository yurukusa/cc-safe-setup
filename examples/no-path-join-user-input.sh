CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "path\.(join|resolve)\(.*req\." && echo "WARNING: Path traversal risk" >&2
exit 0
