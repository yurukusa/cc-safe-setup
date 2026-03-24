CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
IMPORTS=$(echo "$CONTENT" | grep -cE "^(import|from|require)" || echo 0); [ "$IMPORTS" -gt 20 ] && echo "NOTE: $IMPORTS imports — consider splitting module" >&2
exit 0
