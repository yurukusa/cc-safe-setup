# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r ".tool_input.new_string // empty" 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "process\.env\.[a-z]" && echo "NOTE: Lowercase env var name — convention is UPPER_CASE" >&2
exit 0
