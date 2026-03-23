#!/bin/bash
# ================================================================
# tmp-cleanup.sh — Clean up /tmp/claude-*-cwd temp files
# ================================================================
# PURPOSE:
#   Claude Code creates /tmp/claude-{hex}-cwd files to track working
#   directory changes but never deletes them. Over time, thousands
#   accumulate.
#
#   This hook runs on session end and cleans up stale files.
#
#   GitHub #8856 (67 reactions, 102 comments) — the most reported
#   resource leak in Claude Code.
#
# TRIGGER: Stop
# MATCHER: ""
#
# WHAT IT CLEANS:
#   - /tmp/claude-*-cwd (working directory tracking files, ~22 bytes each)
#   - Only files older than 1 hour (to avoid cleaning active sessions)
#
# WHAT IT DOES NOT CLEAN:
#   - /tmp/claude-* directories (may be in use by other sessions)
#   - Any non-claude temp files
# ================================================================

# Clean up stale cwd tracking files (older than 60 minutes)
find /tmp -maxdepth 1 -name 'claude-*-cwd' -type f -mmin +60 -delete 2>/dev/null

# Count remaining (for logging)
REMAINING=$(find /tmp -maxdepth 1 -name 'claude-*-cwd' -type f 2>/dev/null | wc -l)
if [ "$REMAINING" -gt 100 ]; then
    echo "NOTE: $REMAINING claude-*-cwd files remain in /tmp (active sessions)" >&2
fi

exit 0
