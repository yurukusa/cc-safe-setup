# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r ".tool_input.command // empty" 2>/dev/null)
echo "$COMMAND" | grep -qE "git\s+add.*\.(zip|tar|bin|exe)" && [ ! -f ".gitattributes" ] && echo "NOTE: Binary file without .gitattributes LFS config" >&2
exit 0
