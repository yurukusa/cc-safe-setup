CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "parseXML|xml2js|DOMParser|libxml" && echo "$CONTENT" | grep -q "ENTITY" && echo "WARNING: Possible XXE in XML parsing" >&2
exit 0
