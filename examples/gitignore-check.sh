COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+add' || exit 0
if [ ! -f ".gitignore" ] || [ ! -s ".gitignore" ]; then
    echo "WARNING: .gitignore is missing or empty." >&2
    echo "Create one before staging files." >&2
fi
exit 0
