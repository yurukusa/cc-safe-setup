CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "setCookie|res\.cookie" && ! echo "$CONTENT" | grep -q "secure" && echo "NOTE: Cookie without secure flag" >&2
exit 0
