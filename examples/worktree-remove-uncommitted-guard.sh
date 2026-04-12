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
