#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+push\b' || exit 0
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)
if [ -n "$BASE" ]; then
    BAD_COMMITS=$(git log --oneline "$BASE"..HEAD 2>/dev/null | grep -iE '^[a-f0-9]+ (fixup!|squash!|amend!|WIP:?|wip:?|FIXME:?|TODO:?) ')
    if [ -n "$BAD_COMMITS" ]; then
        echo "WARNING: Branch contains uncommitted fixup/WIP commits:" >&2
        echo "$BAD_COMMITS" | head -5 >&2
        echo "" >&2
        echo "Consider: git rebase -i $BASE to squash these before pushing." >&2
    fi
fi
exit 0
