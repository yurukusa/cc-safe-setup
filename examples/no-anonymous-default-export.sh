#!/bin/bash
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
CONTENT=$(cat | jq -r ".tool_input.new_string // empty" 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "export default function\s*\(" && echo "NOTE: Anonymous default export — name for better debugging" >&2
exit 0
