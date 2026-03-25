#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -q "<head" && ! echo "$CONTENT" | grep -q "favicon" && echo "NOTE: Missing favicon link" >&2
exit 0
