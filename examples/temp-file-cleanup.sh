#!/bin/bash
# temp-file-cleanup.sh — Stop hook
# Trigger: Stop
# Matcher: (empty — runs on session end)
#
# Cleans up temporary files created by Claude Code sessions.
# Claude Code creates /tmp/claude-*-cwd files for directory tracking
# but never deletes them, accumulating 500+ files/day.
#
# See: https://github.com/anthropics/claude-code/issues/8856
#
# Usage: Add to settings.json as a Stop hook
#
# {
#   "hooks": {
#     "Stop": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash /path/to/temp-file-cleanup.sh" }]
#     }]
#   }
# }

# Count before cleanup
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COUNT=$(find /tmp -maxdepth 1 -name "claude-*" -type f 2>/dev/null | wc -l)

if [ "$COUNT" -eq 0 ]; then
    exit 0
fi

# Clean up Claude Code temp files older than 1 hour
find /tmp -maxdepth 1 -name "claude-*-cwd" -type f -mmin +60 -delete 2>/dev/null
find /tmp -maxdepth 1 -name "claude-*" -type f -mmin +60 -delete 2>/dev/null

REMAINING=$(find /tmp -maxdepth 1 -name "claude-*" -type f 2>/dev/null | wc -l)
CLEANED=$((COUNT - REMAINING))

if [ "$CLEANED" -gt 0 ]; then
    echo "Cleaned $CLEANED Claude temp files (${REMAINING} recent files kept)" >&2
fi

exit 0
