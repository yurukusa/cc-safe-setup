#!/bin/bash
# read-all-files-enforcer.sh — Track which files have been read in a directory
#
# Solves: Agent skips files when told to "read every file" (#40389).
#         Claude delegates to subagents, summarizes instead of reading,
#         or substitutes its own judgment about what needs reading.
#
# How it works: PostToolUse hook on Read that logs read files.
#   Paired with a manual check: after the user says "read all files in X",
#   compare the log against actual directory contents.
#
# Usage: Set CC_READ_TRACK_DIR to the target directory.
#   export CC_READ_TRACK_DIR="docs/"
#   After the task, check: diff <(ls docs/) <(cat /tmp/claude-read-log-*)
#
# TRIGGER: PostToolUse
# MATCHER: "Read"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Read" ] || exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

TRACK_DIR="${CC_READ_TRACK_DIR:-}"
[ -n "$TRACK_DIR" ] || exit 0

# Check if the read file is in the tracked directory
case "$FILE" in
    ${TRACK_DIR}*)
        # Log the read
        LOG_FILE="/tmp/claude-read-track-${PPID:-0}"
        echo "$FILE" >> "$LOG_FILE"

        # Count total files in directory vs read files
        TOTAL=$(find "$TRACK_DIR" -type f 2>/dev/null | wc -l)
        READ_COUNT=$(sort -u "$LOG_FILE" 2>/dev/null | wc -l)

        if [ "$READ_COUNT" -lt "$TOTAL" ]; then
            REMAINING=$((TOTAL - READ_COUNT))
            echo "Progress: $READ_COUNT/$TOTAL files read in $TRACK_DIR ($REMAINING remaining)" >&2
        else
            echo "All $TOTAL files in $TRACK_DIR have been read." >&2
        fi
        ;;
esac

exit 0
