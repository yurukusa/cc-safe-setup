#!/bin/bash
# react-key-warn.sh — Warn about missing key props in JSX lists
#
# Prevents: "Each child in a list should have a unique key prop" errors.
#           Claude often generates .map() without key props.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.jsx|*.tsx) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE" ] && exit 0

# Check for .map( without key= in the return
if grep -qE '\.map\s*\(' "$FILE"; then
  # Count map calls and key props
  MAPS=$(grep -c '\.map\s*(' "$FILE" 2>/dev/null || echo 0)
  KEYS=$(grep -c 'key=' "$FILE" 2>/dev/null || echo 0)
  if [ "$MAPS" -gt "$KEYS" ]; then
    echo "WARNING: $FILE has $MAPS .map() calls but only $KEYS key= props." >&2
    echo "  Add key props to list items to avoid React warnings." >&2
  fi
fi

exit 0
