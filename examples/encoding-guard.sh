#!/bin/bash
# encoding-guard.sh — Warn when writing to non-UTF-8 files
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0
ENC=$(file -bi "$FILE" 2>/dev/null | grep -oE 'charset=[^ ;]+' | cut -d= -f2)
if [ -n "$ENC" ] && [ "$ENC" != "utf-8" ] && [ "$ENC" != "us-ascii" ] && [ "$ENC" != "binary" ]; then
    echo "WARNING: $FILE has encoding $ENC (not UTF-8)." >&2
    echo "Writing UTF-8 content may cause corruption." >&2
fi
exit 0
