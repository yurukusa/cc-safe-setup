CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
if echo "$CONTENT" | grep -qE "http://localhost:[0-9]+|http://127\.0\.0\.1"; then echo "NOTE: Hardcoded localhost URL — use env var instead" >&2; fi
exit 0
