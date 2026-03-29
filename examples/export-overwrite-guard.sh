#!/bin/bash
# export-overwrite-guard.sh — Prevent /export from overwriting existing files
#
# Solves: /export command overwrites files without warning (#37595).
#         Users lose existing files when Claude exports to the same path.
#
# How it works: PreToolUse hook on Write that checks if the target file
#   exists and contains content. If so, warns before allowing overwrite.
#
# TRIGGER: PreToolUse
# MATCHER: "Write"

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Check if file exists and has content
if [ -f "$FILE" ] && [ -s "$FILE" ]; then
  SIZE=$(wc -c < "$FILE" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 100 ]; then
    echo "WARNING: Overwriting existing file '$FILE' ($SIZE bytes)." >&2
    echo "Consider writing to a different path or backing up first." >&2
    # Don't block — just warn via stderr
  fi
fi

exit 0
