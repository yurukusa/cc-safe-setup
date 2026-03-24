CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "localStorage\.setItem.*password|sessionStorage.*token" && echo "WARNING: Storing secrets in browser storage" >&2
exit 0
