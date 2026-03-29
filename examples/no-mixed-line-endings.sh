#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
if echo "$CONTENT" | grep -qP "\r\n" && echo "$CONTENT" | grep -qP "[^\r]\n"; then echo "NOTE: Mixed line endings (CRLF + LF)" >&2; fi
exit 0
