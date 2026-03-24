# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r ".tool_input.command // empty" 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "rm\s+.*\*"; then echo "WARNING: rm with wildcard pattern" >&2; fi
exit 0
