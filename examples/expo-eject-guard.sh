#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'expo\s+eject|npx\s+expo\s+eject'; then
    echo "BLOCKED: Expo eject is irreversible." >&2
    echo "Command: $COMMAND" >&2
    echo "Consider: expo prebuild (reversible alternative)" >&2
    exit 2
fi
exit 0
