#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "^\s+\w+\.\w+\(" && echo "$CONTENT" | grep -q "await\|\.then\|\.catch" || echo "$CONTENT" | grep -qE "async" && echo "NOTE: Check for unhandled promises" >&2
exit 0
