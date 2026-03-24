CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
LINES=$(echo "$CONTENT" | wc -l); [ "$LINES" -gt 100 ] && echo "NOTE: Edit adds 100+ lines — consider splitting" >&2
exit 0
