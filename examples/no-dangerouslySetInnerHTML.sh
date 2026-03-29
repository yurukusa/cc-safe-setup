#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -q "dangerouslySetInnerHTML" && echo "WARNING: XSS risk via dangerouslySetInnerHTML" >&2
exit 0
