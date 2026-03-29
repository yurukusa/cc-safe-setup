#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'spring\.profiles\.active=prod|SPRING_PROFILES_ACTIVE=prod'; then
    echo "WARNING: Running Spring with production profile." >&2
    echo "This connects to production database and services." >&2
fi
exit 0
