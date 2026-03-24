CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "TLSv1[^.]|SSLv3" && echo "WARNING: Weak TLS version" >&2
exit 0
