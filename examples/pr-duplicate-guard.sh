# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-pr-duplicate-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [pr-duplicate-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
