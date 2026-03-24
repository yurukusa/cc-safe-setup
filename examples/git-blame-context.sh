#!/bin/bash
# ================================================================
# git-blame-context.sh — Show file ownership before major edits
# ================================================================
# PURPOSE:
#   Before Claude rewrites a file, show who wrote most of it.
#   Helps prevent accidentally breaking code you don't understand
#   the history of. Especially useful in team repositories.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Only warn on substantial edits (old_string > 10 lines)
OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
[ -z "$OLD" ] && exit 0
OLD_LINES=$(echo "$OLD" | wc -l)
[ "$OLD_LINES" -lt 10 ] && exit 0

# Get top contributors for this file
CONTRIBUTORS=$(git log --format='%an' -- "$FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -3)
if [ -n "$CONTRIBUTORS" ]; then
    TOTAL_COMMITS=$(git log --oneline -- "$FILE" 2>/dev/null | wc -l)
    LAST_AUTHOR=$(git log -1 --format='%an' -- "$FILE" 2>/dev/null)
    echo "NOTE: Editing $OLD_LINES+ lines in $FILE" >&2
    echo "  Last edited by: $LAST_AUTHOR" >&2
    echo "  Top contributors ($TOTAL_COMMITS commits):" >&2
    echo "$CONTRIBUTORS" | head -3 | sed 's/^/    /' >&2
fi

exit 0
