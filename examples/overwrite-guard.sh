#!/bin/bash
# ================================================================
# overwrite-guard.sh — Warn before overwriting existing files
# ================================================================
# PURPOSE:
#   Claude's Write tool can silently overwrite files without
#   confirmation. This hook warns when a Write targets a file
#   that already exists, giving visibility into potential data loss.
#
# TRIGGER: PreToolUse  MATCHER: "Write"
#
# Born from: https://github.com/anthropics/claude-code/issues/37595
#   "/export overwrites existing files without warning"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Expand ~ to home directory
FILE="${FILE/#\~/$HOME}"

if [ -f "$FILE" ]; then
    SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 0 ]; then
        LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)
        echo "WARNING: Overwriting existing file: $FILE ($LINES lines, $SIZE bytes)" >&2
        echo "Use Edit tool instead to make targeted changes." >&2
    fi
fi

exit 0
