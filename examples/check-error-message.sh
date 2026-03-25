#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "throw new Error\(['\"](error|Error|something went wrong)" && echo "NOTE: Generic error message — be specific" >&2
exit 0
