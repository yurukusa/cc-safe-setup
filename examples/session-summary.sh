#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
echo "" >&2
echo "=== Session Summary ===" >&2
BRANCH=$(git branch --show-current 2>/dev/null)
COMMITS=$(git log --oneline --since="1 hour ago" 2>/dev/null | wc -l)
DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
[ -n "$BRANCH" ] && echo "Branch: $BRANCH | Commits(1h): $COMMITS | Uncommitted: $DIRTY" >&2
echo "========================" >&2
exit 0
