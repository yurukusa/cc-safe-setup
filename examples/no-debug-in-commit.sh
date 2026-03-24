COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
echo "$COMMAND" | grep -qE 'git\s+commit' || exit 0
git diff --cached 2>/dev/null | grep -qE '^\+.*(debugger|pdb\.set_trace)' && echo "WARNING: Debug in staged" >&2
exit 0
