#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "\.then\(" && ! echo "$CONTENT" | grep -q "\.catch" && echo "NOTE: Promise without .catch()" >&2
exit 0
