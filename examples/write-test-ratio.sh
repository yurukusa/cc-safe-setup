COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE "^\s*git\s+commit" || exit 0; S=$(git diff --cached --name-only 2>/dev/null | grep -cvE "test|spec" || echo 0); T=$(git diff --cached --name-only 2>/dev/null | grep -cE "test|spec" || echo 0); [ "$S" -gt 5 ] && [ "$T" -eq 0 ] && echo "WARNING: $S source files, 0 test files" >&2
exit 0
