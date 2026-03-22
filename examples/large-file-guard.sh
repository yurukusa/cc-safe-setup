#!/bin/bash
# large-file-guard.sh — Warn when Write tool creates oversized files
#
# Solves: Claude generating multi-MB files that bloat the repo,
# or accidentally writing binary/base64 data to source files.
#
# This is a PostToolUse hook — it checks AFTER the write happens
# and warns if the file is suspiciously large.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/large-file-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ "$TOOL" != "Write" ]] && exit 0
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0

# Check file size (default threshold: 500KB)
MAX_SIZE=${CC_MAX_FILE_SIZE:-512000}
FILE_SIZE=$(stat -c %s "$FILE" 2>/dev/null || stat -f %z "$FILE" 2>/dev/null || echo 0)

if (( FILE_SIZE > MAX_SIZE )); then
    SIZE_KB=$((FILE_SIZE / 1024))
    echo "" >&2
    echo "WARNING: Large file written: $FILE (${SIZE_KB}KB)" >&2
    echo "This may indicate generated binary/base64 data in a source file." >&2
    echo "Threshold: $((MAX_SIZE / 1024))KB (set CC_MAX_FILE_SIZE to adjust)" >&2
fi

exit 0
