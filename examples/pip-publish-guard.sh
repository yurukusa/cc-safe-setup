INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'twine\s+upload|python.*setup\.py\s+upload'; then
    echo "BLOCKED: PyPI upload." >&2
    echo "Command: $COMMAND" >&2
    echo "Publishing packages should be done manually or via CI." >&2
    exit 2
fi
exit 0
