#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "(state\.\w+\s*=|\.push\(|\.splice\()" && echo "$CONTENT" | grep -q "reducer\|Reducer" && echo "WARNING: Direct state mutation in reducer" >&2
exit 0
