CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "^import.*from" && echo "$CONTENT" | grep -cE "^import" | xargs -I{} test {} -gt 10 && echo "NOTE: Many imports — check for unused ones" >&2
exit 0
