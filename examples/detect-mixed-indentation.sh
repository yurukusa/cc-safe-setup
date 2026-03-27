#!/bin/bash
# detect-mixed-indentation.sh — Warn about mixed tabs/spaces
#
# Prevents: Indentation errors from mixing tabs and spaces.
#           Common when Claude pastes code from different sources.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# Skip binary files and makefiles (which require tabs)
case "$(basename "$FILE")" in
  Makefile|makefile|GNUmakefile) exit 0 ;;
esac

case "$FILE" in
  *.py|*.js|*.ts|*.tsx|*.jsx|*.yaml|*.yml|*.rb|*.go) ;;
  *) exit 0 ;;
esac

HAS_TABS=$(grep -cP '^\t' "$FILE" 2>/dev/null || echo 0)
HAS_SPACES=$(grep -cP '^ {2,}' "$FILE" 2>/dev/null || echo 0)

if [ "$HAS_TABS" -gt 0 ] && [ "$HAS_SPACES" -gt 0 ]; then
  echo "WARNING: Mixed tabs and spaces in $FILE ($HAS_TABS tab-lines, $HAS_SPACES space-lines)." >&2
  echo "  Standardize to one indentation style." >&2
fi

exit 0
