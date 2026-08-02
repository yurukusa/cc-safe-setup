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

# grep -c は0件でも "0" を出して終了コード1を返す。`|| echo 0` を付けると
# "0" が二重に出て以降の数値比較が毎回壊れる（origin/main で実際に起きていた）
HAS_TABS=$(grep -cE "^$(printf '\t')" "$FILE" 2>/dev/null)
HAS_SPACES=$(grep -cE '^  +' "$FILE" 2>/dev/null)
[ -z "$HAS_TABS" ] && HAS_TABS=0
[ -z "$HAS_SPACES" ] && HAS_SPACES=0

if [ "$HAS_TABS" -gt 0 ] && [ "$HAS_SPACES" -gt 0 ]; then
  echo "WARNING: Mixed tabs and spaces in $FILE ($HAS_TABS tab-lines, $HAS_SPACES space-lines)." >&2
  echo "  Standardize to one indentation style." >&2
fi

exit 0
