#!/bin/bash
# ================================================================
# post-compact-restore.sh — Restore context after /compact
# ================================================================
# PURPOSE:
#   After /compact, Claude loses track of the current branch,
#   recent files, and task state. This Stop hook outputs key
#   state info to stderr so Claude sees it in the next turn.
#
# TRIGGER: Stop  MATCHER: ""
#
# Reads .claude/session-snapshot.md if it exists (from context-snapshot).
# Falls back to git state.
# ================================================================

# Check if we're in a post-compact state (tool count reset or snapshot exists)
SNAPSHOT=".claude/session-snapshot.md"

if [ -f "$SNAPSHOT" ]; then
    echo "" >&2
    echo "=== Session State (from snapshot) ===" >&2
    cat "$SNAPSHOT" | head -20 >&2
    echo "===================================" >&2
    exit 0
fi

# Fallback: basic git state
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
    LAST=$(git log --oneline -1 2>/dev/null)
    echo "" >&2
    echo "Branch: $BRANCH | Uncommitted: $DIRTY | Last: $LAST" >&2
fi

exit 0
