COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "TZ=|--timezone" && ! echo "$COMMAND" | grep -q "UTC"; then echo "NOTE: Non-UTC timezone in command" >&2; fi
exit 0
