#!/bin/bash
# ================================================================
# read-before-edit.sh — Warn when editing files not recently read
# ================================================================
# PURPOSE:
#   Claude Code sometimes tries to Edit files it hasn't Read,
#   leading to old_string mismatches. This hook tracks which
#   files were recently Read and warns when Edit targets an
#   unread file.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit"
#
# HOW IT WORKS:
#   - PostToolUse Read hook records file paths to /tmp/cc-read-files
#   - This PreToolUse Edit hook checks if the target was read
#   - Warns (doesn't block) if file wasn't read recently
#
# NOTE: Requires companion PostToolUse hook to record Read events.
#   Or just install this and accept the warning.
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only check Edit tool
if [[ "$TOOL" != "Edit" ]] || [[ -z "$FILE" ]]; then
    exit 0
fi

READ_LOG="/tmp/cc-read-files"

# Check if file was recently read
if [ -f "$READ_LOG" ]; then
    if grep -qF "$FILE" "$READ_LOG" 2>/dev/null; then
        exit 0  # File was read, safe to edit
    fi
fi

echo "NOTE: Editing $FILE without reading it first." >&2
echo "Consider using Read before Edit to avoid old_string mismatches." >&2

exit 0
