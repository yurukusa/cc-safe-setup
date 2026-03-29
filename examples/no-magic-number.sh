#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "= [0-9]{4,}[^.0-9]|setTimeout\([^,]+,\s*[0-9]{4}" && echo "NOTE: Magic number detected. Consider using a named constant." >&2
exit 0
