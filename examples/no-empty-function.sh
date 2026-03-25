#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "(function|=>)\s*\{[\s\n]*\}" && echo "NOTE: Empty function body" >&2
exit 0
