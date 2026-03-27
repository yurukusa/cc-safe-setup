#!/bin/bash
# read-budget-guard.sh — Limit excessive file reading to prevent token waste
#
# Solves: Claude reading far more files than necessary, consuming 25% of
# quota before any real work begins. Prevents duplicate reads.
# See: https://github.com/anthropics/claude-code/issues/38733
#
# TRIGGER: PreToolUse
# MATCHER: Read
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Read",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/read-budget-guard.sh"
#       }]
#     }]
#   }
# }
#
# Config via env vars:
#   CC_READ_BUDGET=100    — max unique files per session (default: 100)
#   CC_READ_WARN=50       — warn threshold (default: 50)

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

BUDGET=${CC_READ_BUDGET:-100}
WARN=${CC_READ_WARN:-50}
TRACKER="/tmp/cc-read-budget-$$"

# Create tracker if needed
[ -f "$TRACKER" ] || touch "$TRACKER"

# Check for duplicate read
if grep -qxF "$FILE" "$TRACKER" 2>/dev/null; then
    echo "⚠ Duplicate read: $(basename "$FILE") was already read this session" >&2
    echo "  Consider using the cached content instead of re-reading." >&2
    # Allow but warn (don't block duplicate reads, just flag them)
fi

# Track this read
echo "$FILE" >> "$TRACKER"
COUNT=$(wc -l < "$TRACKER")

# Check budget
if [ "$COUNT" -gt "$BUDGET" ]; then
    echo "BLOCKED: Read budget exceeded ($COUNT/$BUDGET files)" >&2
    echo "You've read $COUNT unique files this session." >&2
    echo "Start working with what you have, or increase CC_READ_BUDGET." >&2
    exit 2
fi

if [ "$COUNT" -eq "$WARN" ]; then
    echo "⚠ Read budget warning: $COUNT/$BUDGET files read" >&2
    echo "  Focus on implementation rather than reading more files." >&2
fi

exit 0
