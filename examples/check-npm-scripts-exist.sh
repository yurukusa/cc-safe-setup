#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
FILE=$(cat | jq -r ".tool_input.file_path // empty" 2>/dev/null); case "$FILE" in *package.json) ;; *) exit 0;; esac; echo "$CONTENT" | grep -qE "npm run [a-z]+" && echo "NOTE: Verify referenced npm scripts exist" >&2
exit 0
