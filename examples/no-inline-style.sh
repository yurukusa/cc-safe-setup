#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "style=\"|style={" && echo "NOTE: Inline styles detected. Consider CSS classes." >&2
exit 0
