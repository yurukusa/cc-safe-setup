#!/bin/bash
# ================================================================
# auto-stash-before-pull.sh — Suggest stash before git pull/merge
# ================================================================
# PURPOSE:
#   Claude runs git pull/merge with uncommitted changes, causing
#   merge conflicts or lost work. This hook warns and suggests
#   git stash before pull/merge/rebase operations.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check pull/merge/rebase
echo "$COMMAND" | grep -qE '\bgit\s+(pull|merge|rebase)\b' || exit 0

# Check for uncommitted changes
DIRTY=$(git status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
    COUNT=$(echo "$DIRTY" | wc -l)
    echo "WARNING: git pull/merge/rebase with $COUNT uncommitted change(s)." >&2
    echo "Consider running: git stash && git pull && git stash pop" >&2
fi

exit 0
