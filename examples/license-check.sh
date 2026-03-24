#!/bin/bash
# license-check.sh — Warn when creating files without a license header
# TRIGGER: PostToolUse  MATCHER: "Write"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
case "$FILE" in *.js|*.ts|*.py|*.go|*.rs|*.java|*.rb|*.sh) ;; *) exit 0 ;; esac
[ ! -f "$FILE" ] && exit 0
if ! head -5 "$FILE" | grep -qiE '(license|copyright|MIT|Apache|GPL)'; then
  if [ -f "LICENSE" ] || [ -f "LICENSE.md" ]; then
    echo "NOTE: New source file $FILE has no license header." >&2
  fi
fi
exit 0
