# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-worktree-remove-uncommitted-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [worktree-remove-uncommitted-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INFO=$(cat)
PATH_WT=$(echo "$INFO" | jq -r '.path // empty' 2>/dev/null)
[ -z "$PATH_WT" ] && exit 0
[ ! -d "$PATH_WT" ] && exit 0
cd "$PATH_WT" 2>/dev/null || exit 0
DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
if [ "$DIRTY" -gt 0 ]; then
    echo "BLOCKED: Worktree at $PATH_WT has $DIRTY uncommitted change(s)." >&2
    echo "Commit or stash changes before removing." >&2
    exit 2
fi
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ]; then
    UNPUSHED=$(git log --oneline "origin/$BRANCH..$BRANCH" 2>/dev/null | wc -l)
    if [ "$UNPUSHED" -gt 0 ]; then
        echo "WARNING: $UNPUSHED unpushed commit(s) on $BRANCH." >&2
        echo "Push before removing: git push origin $BRANCH" >&2
    fi
fi
exit 0
