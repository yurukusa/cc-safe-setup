#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0
case "$FILE" in *.ts|*.js|*.tsx|*.jsx) ;; *) exit 0 ;; esac
# -P は GNU 拡張。BSD grep では警告が黙って消えるので -E にする。
if grep -qE 'eval[[:space:]]*\(`|new Function[[:space:]]*\(`' "$FILE" 2>/dev/null; then
    echo "WARNING: eval() or new Function() with template literal." >&2
    echo "File: $(basename "$FILE")" >&2
    echo "This is a code injection risk." >&2
fi
exit 0
