#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
FILE=$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$FILE" in *Dockerfile*) ;; *) exit 0;; esac
CONTENT=$(cat | jq -r '.tool_input.new_string // empty' 2>/dev/null)
echo "$CONTENT" | grep -qE "^RUN.*apt-get.*install" && echo "NOTE: Clean apt cache in Dockerfile" >&2
exit 0
