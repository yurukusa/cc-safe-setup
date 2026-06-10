#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "Promise\.all\(" && ! echo "$CONTENT" | grep -qE "\.catch|try " && echo "NOTE: Promise.all() without .catch()/try — one rejection fails the whole batch" >&2
exit 0
