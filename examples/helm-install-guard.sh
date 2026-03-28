INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'helm\s+(install|upgrade).*(-n|--namespace)\s*(prod|production)'; then
    echo "WARNING: Helm deploy to production namespace." >&2
    echo "Command: $COMMAND" >&2
fi
exit 0
