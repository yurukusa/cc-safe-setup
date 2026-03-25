#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "http://[^l]" && ! echo "$CONTENT" | grep -q "localhost" && echo "NOTE: http:// without TLS" >&2
exit 0
