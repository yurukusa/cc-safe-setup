#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$FILE" in *package.json) ;; *) exit 0;; esac
CONTENT=$(cat | jq -r '.tool_input.new_string // empty' 2>/dev/null)
DEPS=$(echo "$CONTENT" | grep -c '":' || echo 0)
[ "$DEPS" -gt 50 ] && echo "NOTE: $DEPS deps — consider reducing" >&2
exit 0
