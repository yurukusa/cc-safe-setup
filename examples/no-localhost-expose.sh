COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "0\.0\.0\.0|INADDR_ANY|--host\s+0"; then echo "WARNING: Binding to all interfaces exposes service to network" >&2; fi
exit 0
