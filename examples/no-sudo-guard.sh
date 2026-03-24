COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*sudo\s'; then
    echo "BLOCKED: sudo command detected." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi
exit 0
