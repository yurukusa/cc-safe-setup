#!/bin/bash
# edit-old-string-validator.sh — Pre-validate Edit tool old_string exists
#
# Solves: Parallel Edit tool calls cascade-fail when one Edit's
#         old_string doesn't match the file content (#22264).
#         By catching mismatches before execution, sibling
#         edits in the same batch can proceed normally.
#
# How it works: Reads the Edit tool input, checks if old_string
#   exists in the target file. If not found, blocks with exit 2
#   and a descriptive error message.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit"

set -euo pipefail
INPUT=$(cat)

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)

# Skip if no file or old_string
[ -z "$FILE" ] && exit 0
[ -z "$OLD_STRING" ] && exit 0

# Skip if file doesn't exist (Edit tool will handle that error)
[ ! -f "$FILE" ] && exit 0

# Check if old_string exists in the file
if ! grep -qF "$OLD_STRING" "$FILE" 2>/dev/null; then
  echo "BLOCKED: old_string not found in $FILE." >&2
  echo "The file may have been modified by a prior edit in this batch." >&2
  echo "Re-read the file to get the current content before retrying." >&2
  exit 2
fi

exit 0
