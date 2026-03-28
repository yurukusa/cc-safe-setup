INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'go\s+mod\s+tidy'; then
    echo "NOTE: go mod tidy will remove unused dependencies from go.mod." >&2
    echo "Commit go.mod/go.sum first if you want to preserve them." >&2
fi
exit 0
