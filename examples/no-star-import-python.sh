#!/bin/bash
# no-star-import-python.sh — Warn about `from module import *` in Python
#
# Prevents: Namespace pollution from wildcard imports.
#           Makes it unclear where names come from.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.py) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

STARS=$(grep -nE '^from\s+\S+\s+import\s+\*' "$FILE" | head -3)
if [ -n "$STARS" ]; then
  echo "WARNING: Wildcard import found in $FILE:" >&2
  echo "$STARS" | sed 's/^/  /' >&2
  echo "  Use explicit imports instead." >&2
fi

exit 0
