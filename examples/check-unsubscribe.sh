#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "addEventListener\(" && ! echo "$CONTENT" | grep -qE "removeEventListener" && echo "NOTE: addEventListener without a matching removeEventListener" >&2
exit 0
