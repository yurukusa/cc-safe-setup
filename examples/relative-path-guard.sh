#!/bin/bash
# relative-path-guard.sh — Warn on relative file paths in Edit/Write
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
# Born from: https://github.com/anthropics/claude-code/issues/38270
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0
if [[ ! "$FILE" = /* ]]; then
    ABS=$(realpath -m "$FILE" 2>/dev/null || echo "$PWD/$FILE")
    echo "WARNING: Relative path: $FILE → $ABS" >&2
    echo "Claude may be targeting the wrong file." >&2
fi
exit 0
