#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "__proto__|Object\.assign\(\{\}," && echo "WARNING: Potential prototype pollution" >&2
exit 0
