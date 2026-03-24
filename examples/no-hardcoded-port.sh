CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE ":(3000|8080|8000|5000|4000)[^0-9]" && echo "NOTE: Hardcoded port number — use env var" >&2
exit 0
