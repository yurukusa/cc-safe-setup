#!/bin/bash
# ================================================================
# revert-helper.sh — Show revert command when session ends badly
# ================================================================
# PURPOSE:
#   When a Claude Code session ends (Stop event), check if there
#   are uncommitted changes and show a one-line revert command.
#   Makes it easy to undo everything Claude did if it went wrong.
#
# TRIGGER: Stop  MATCHER: ""
# ================================================================

# Check if we're in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Check for uncommitted changes
DIRTY=$(git status --porcelain 2>/dev/null)
[ -z "$DIRTY" ] && exit 0

COUNT=$(echo "$DIRTY" | wc -l)
LAST_COMMIT=$(git log --oneline -1 2>/dev/null | head -c 50)

echo "" >&2
echo "Session ended with $COUNT uncommitted change(s)." >&2
echo "Last commit: $LAST_COMMIT" >&2
echo "" >&2
echo "To undo all changes:" >&2
echo "  git checkout -- . && git clean -fd" >&2
echo "" >&2
echo "To review changes:" >&2
echo "  git diff --stat" >&2

exit 0
