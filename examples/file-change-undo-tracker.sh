#!/bin/bash
# file-change-undo-tracker.sh — Track file changes for easy undo
#
# Solves: After Claude makes unwanted changes across multiple files,
#         users have no easy way to identify and revert all affected files.
#         git diff works but only for tracked files.
#
# How it works: FileChanged hook that logs every file modification
#   with timestamp and change type. Creates a revert script
#   that can undo all changes from the current session.
#
# Usage: After session, run: bash /tmp/claude-undo-session.sh
#
# TRIGGER: FileChanged
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.file // empty' 2>/dev/null)
EVENT=$(echo "$INPUT" | jq -r '.event // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

LOG_FILE="/tmp/claude-file-changes-${PPID:-0}.log"
UNDO_FILE="/tmp/claude-undo-session-${PPID:-0}.sh"
TIMESTAMP=$(date +"%H:%M:%S")

# Log the change
echo "${TIMESTAMP} ${EVENT:-modified} ${FILE}" >> "$LOG_FILE"

# Track for undo (git-tracked files only)
if git ls-files --error-unmatch "$FILE" &>/dev/null 2>&1; then
    # File is git-tracked — can be reverted with git checkout
    if ! grep -qF "git checkout -- \"$FILE\"" "$UNDO_FILE" 2>/dev/null; then
        echo "git checkout -- \"$FILE\"  # ${EVENT:-modified} at ${TIMESTAMP}" >> "$UNDO_FILE"
    fi
fi

# Count changes
COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
if [ "$((COUNT % 10))" -eq 0 ] && [ "$COUNT" -gt 0 ]; then
    echo "Session file changes: $COUNT files modified. Undo: bash $UNDO_FILE" >&2
fi

exit 0
