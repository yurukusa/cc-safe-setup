#!/bin/bash
# large-file-write-guard.sh — Warn when writing large files
#
# Prevents: Accidental creation of huge files that bloat the repo.
#           Claude sometimes generates entire datasets, logs, or
#           copy-pasted documentation as single files.
#
# Default threshold: 100KB (configurable via CC_MAX_FILE_SIZE)
#
# TRIGGER: PostToolUse
# MATCHER: "Write"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/large-file-write-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

MAX_SIZE="${CC_MAX_FILE_SIZE:-102400}"  # 100KB default

FILE_SIZE=$(wc -c < "$FILE" 2>/dev/null)
[ -z "$FILE_SIZE" ] && exit 0

if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
  SIZE_KB=$((FILE_SIZE / 1024))
  MAX_KB=$((MAX_SIZE / 1024))
  echo "WARNING: Large file written: $FILE (${SIZE_KB}KB > ${MAX_KB}KB limit)" >&2
  echo "  Consider splitting into smaller files or using .gitignore." >&2
fi

exit 0
