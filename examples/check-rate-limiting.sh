#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "app\.(get|post|put|delete)\(" && ! echo "$CONTENT" | grep -q "rateLimit" && echo "NOTE: API endpoint without rate limiting" >&2
exit 0
