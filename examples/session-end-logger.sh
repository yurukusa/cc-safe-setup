#!/bin/bash
# session-end-logger.sh — Log session activity at exit
#
# Solves: No built-in session audit trail. When a session ends,
#         there's no record of what was done unless you manually check
#         git log or conversation history (#40010).
#
# How it works: SessionEnd hook that captures recent git commits,
#   modified files, and session metadata into a structured log file.
#
# TRIGGER: SessionEnd
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionEnd": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-end-logger.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

LOG_DIR=".claude/session-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d').md"

{
    echo ""
    echo "## Session $SESSION_ID — $(date '+%H:%M')"
    echo ""

    # Recent git activity
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        COMMITS=$(git log --oneline --since="1 hour ago" 2>/dev/null)
        if [ -n "$COMMITS" ]; then
            echo "### Commits"
            echo '```'
            echo "$COMMITS"
            echo '```'
        fi

        CHANGED=$(git diff --name-only HEAD~5..HEAD 2>/dev/null | head -20)
        if [ -n "$CHANGED" ]; then
            echo "### Changed files"
            echo '```'
            echo "$CHANGED"
            echo '```'
        fi
    fi

    echo ""
} >> "$LOG_FILE"

exit 0
