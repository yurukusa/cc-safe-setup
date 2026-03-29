#
# TRIGGER: PreToolUse  MATCHER: "Bash"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'gem\s+push\b'; then
    echo "BLOCKED: gem push to RubyGems.org." >&2
    echo "Command: $COMMAND" >&2
    echo "Publishing packages should be done manually." >&2
    exit 2
fi
exit 0
