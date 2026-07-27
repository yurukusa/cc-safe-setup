#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
DEPTH=$(echo "$CONTENT" | grep -c "function\s*("); [ "$DEPTH" -gt 3 ] && echo "NOTE: Possible callback hell ($DEPTH levels)" >&2
exit 0
