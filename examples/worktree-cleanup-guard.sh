#!/bin/bash
# worktree-cleanup-guard.sh — Warn on worktree removal with unmerged commits
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Born from: https://github.com/anthropics/claude-code/issues/38287
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE 'git\s+worktree\s+(remove|prune)' || exit 0
for branch in $(git branch --list 'worktree-*' 2>/dev/null); do
    UNMERGED=$(git log --oneline main..$branch 2>/dev/null | wc -l)
    if [ "$UNMERGED" -gt 0 ]; then
        echo "WARNING: $branch has $UNMERGED unmerged commit(s)." >&2
        echo "Push first: git push origin $branch" >&2
    fi
done
exit 0
