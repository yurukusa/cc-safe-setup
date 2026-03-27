#!/bin/bash
# session-start-safety-check.sh — Warn about uncommitted changes on session start
#
# Solves: Claude Code running destructive git commands on session startup
#         that destroy uncommitted work (#34327, #39394)
#
# How it works:
#   On SessionStart, checks for:
#   1. Uncommitted changes (modified/new files)
#   2. Unpushed commits
#   3. Stashed changes that may need attention
#
#   Prints warnings but does NOT block (exit 0 always).
#   The goal is awareness, not prevention.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-start-safety-check.sh" }]
#     }]
#   }
# }

# Only run in git repos
git rev-parse --git-dir > /dev/null 2>&1 || exit 0

WARNINGS=0

# Check for uncommitted changes
CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
if [ "$CHANGES" -gt 0 ]; then
    echo "⚠ WARNING: $CHANGES uncommitted changes detected." >&2
    echo "  Consider: git stash  (before destructive operations)" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for unpushed commits
UNPUSHED=$(git log --oneline @{upstream}..HEAD 2>/dev/null | wc -l)
if [ "$UNPUSHED" -gt 0 ]; then
    echo "⚠ WARNING: $UNPUSHED unpushed commits." >&2
    echo "  Consider: git push  (to protect against local data loss)" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for stashes
STASHES=$(git stash list 2>/dev/null | wc -l)
if [ "$STASHES" -gt 0 ]; then
    echo "ℹ NOTE: $STASHES stashed changes exist." >&2
    echo "  Review: git stash list" >&2
fi

if [ "$WARNINGS" -eq 0 ]; then
    echo "✓ Working tree clean, all commits pushed." >&2
fi

exit 0
