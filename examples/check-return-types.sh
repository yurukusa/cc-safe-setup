CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "function\s+\w+\([^)]*\)\s*{" && ! echo "$CONTENT" | grep -q ": " && echo "NOTE: Missing return type annotation" >&2
exit 0
