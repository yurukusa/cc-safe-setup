COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE "^\s*npm\s+install" && echo "NOTE: Run npm audit after install" >&2
exit 0
