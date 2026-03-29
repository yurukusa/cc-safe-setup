#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qP '(--(password|token|secret|api-key|auth)\s*=?\s*\S{8,})|(-p\s+\S{8,})'; then
    echo "WARNING: Possible secret in command arguments." >&2
    echo "Secrets in CLI args are visible in process listings and shell history." >&2
    echo "Use environment variables or stdin instead." >&2
fi
exit 0
