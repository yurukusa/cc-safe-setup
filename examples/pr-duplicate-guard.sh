COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '\bgh\s+pr\s+create\b' || exit 0
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$BRANCH" ] && exit 0
EXISTING=$(gh pr list --head "$BRANCH" --state open --json number,title --jq '.[0].number' 2>/dev/null)
if [ -n "$EXISTING" ]; then
    TITLE=$(gh pr list --head "$BRANCH" --state open --json title --jq '.[0].title' 2>/dev/null)
    echo "BLOCKED: An open PR already exists for branch '$BRANCH'." >&2
    echo "  PR #$EXISTING: $TITLE" >&2
    echo "  Update the existing PR instead of creating a new one." >&2
    exit 2
fi
exit 0
