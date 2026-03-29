#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -q "<head" && ! echo "$CONTENT" | grep -q "viewport" && echo "NOTE: Missing viewport meta" >&2
exit 0
