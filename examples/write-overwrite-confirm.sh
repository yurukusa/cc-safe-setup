#!/bin/bash
# write-overwrite-confirm.sh — Warn when Write tool overwrites large files
#
# Solves: Write tool silently replacing large files with new content (#34597).
#         A 500-line file can be overwritten with 10 lines without warning.
#
# How it works: PreToolUse hook on Write that compares the new content
#   size against the existing file. If the new content is significantly
#   smaller, warns about potential data loss.
#
# TRIGGER: PreToolUse
# MATCHER: "Write"

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Skip if file doesn't exist (new file creation)
[ ! -f "$FILE" ] && exit 0

# Get current file size (lines)
CURRENT_LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)

# Get new content size (approximate from JSON length)
NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
NEW_LINES=$(echo "$NEW_CONTENT" | wc -l 2>/dev/null || echo 0)

# Warn if shrinking by more than 50% and file is > 50 lines
if [ "$CURRENT_LINES" -gt 50 ] && [ "$NEW_LINES" -gt 0 ]; then
  RATIO=$((NEW_LINES * 100 / CURRENT_LINES))
  if [ "$RATIO" -lt 50 ]; then
    echo "WARNING: File shrinking from $CURRENT_LINES to ~$NEW_LINES lines ($RATIO%)." >&2
    echo "File: $FILE" >&2
    echo "Consider using Edit tool for targeted changes instead of full rewrite." >&2
  fi
fi

exit 0
