COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bgit\s+submodule\s+(deinit|rm)\b'; then
    echo "WARNING: Removing git submodule. This may break builds." >&2
fi
exit 0
