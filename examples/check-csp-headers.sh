#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "Content-Security-Policy" || (echo "$CONTENT" | grep -q "helmet" && echo "NOTE: Consider adding CSP headers" >&2)
exit 0
