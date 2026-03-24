#!/bin/bash
# auto-push-worktree.sh — Auto-push worktree branches before session end
# TRIGGER: Stop  MATCHER: ""
# Born from: https://github.com/anthropics/claude-code/issues/38287
BRANCH=$(git branch --show-current 2>/dev/null)
[[ "$BRANCH" == worktree-* ]] || exit 0
UNMERGED=$(git log --oneline origin/main..$BRANCH 2>/dev/null | wc -l)
if [ "$UNMERGED" -gt 0 ]; then
    git push origin $BRANCH 2>/dev/null && \
        echo "Auto-pushed $UNMERGED commit(s) from $BRANCH" >&2
fi
exit 0
