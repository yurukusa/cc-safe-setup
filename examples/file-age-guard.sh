#!/bin/bash
# file-age-guard.sh — Warn before editing files not modified in 30+ days
#
# Solves: Claude edits stable/legacy files that haven't been touched
#         in months, introducing regressions in well-tested code.
#
# How it works: PreToolUse hook on Edit/Write that checks the last
#   modification time of the target file. If the file hasn't been
#   modified in CC_FILE_AGE_DAYS (default 30), warns the user.
#
# This doesn't block — just warns. The assumption is that files
# untouched for a long time are stable and should be edited carefully.
#
# CONFIG:
#   CC_FILE_AGE_DAYS=30  (warn threshold in days)
#
# TRIGGER: PreToolUse
# MATCHER: "Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

AGE_THRESHOLD=${CC_FILE_AGE_DAYS:-30}

# Get file modification time
FILE_MTIME=$(stat -c %Y "$FILE" 2>/dev/null)
[ -z "$FILE_MTIME" ] && exit 0

NOW=$(date +%s)
AGE_DAYS=$(( (NOW - FILE_MTIME) / 86400 ))

if [ "$AGE_DAYS" -ge "$AGE_THRESHOLD" ]; then
    FILENAME=$(basename "$FILE")
    echo "⚠ Editing stable file: ${FILENAME} (last modified ${AGE_DAYS} days ago)" >&2
    echo "  This file hasn't been touched in ${AGE_DAYS} days." >&2
    echo "  Verify changes don't break existing behavior." >&2
fi

exit 0
