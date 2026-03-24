CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qiE "password.*admin|pass.*1234|secret.*default" && echo "WARNING: Default credentials" >&2
exit 0
