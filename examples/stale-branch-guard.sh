#!/bin/bash
# ================================================================
# stale-branch-guard.sh — Warn when working on a stale branch
# ================================================================
# PURPOSE:
#   Claude Code can work on a branch that's far behind main,
#   creating merge conflicts. This hook warns when the current
#   branch is 50+ commits behind the default branch.
#
# TRIGGER: PostToolUse
# MATCHER: ""
#
# Only checks every 20 tool calls to avoid overhead.
# ================================================================

COUNTER_FILE="/tmp/cc-stale-branch-check"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Only check every 20 tool calls
[ $((COUNT % 20)) -ne 0 ] && exit 0

# Only check in git repos
[ -d .git ] || exit 0

# Get default branch
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT" ] && DEFAULT="main"

CURRENT=$(git branch --show-current 2>/dev/null)
[ -z "$CURRENT" ] || [ "$CURRENT" = "$DEFAULT" ] && exit 0

# Count commits behind
BEHIND=$(git rev-list --count HEAD..origin/"$DEFAULT" 2>/dev/null || echo 0)

if [ "$BEHIND" -ge 50 ]; then
    echo "WARNING: Branch '$CURRENT' is $BEHIND commits behind $DEFAULT." >&2
    echo "Consider rebasing: git rebase origin/$DEFAULT" >&2
elif [ "$BEHIND" -ge 20 ]; then
    echo "NOTE: Branch '$CURRENT' is $BEHIND commits behind $DEFAULT." >&2
fi

exit 0
