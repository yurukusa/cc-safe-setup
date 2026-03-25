#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "http://" && echo "$CONTENT" | grep -q "redirect" && ! echo "$CONTENT" | grep -q "https" && echo "NOTE: HTTP redirect without HTTPS" >&2
exit 0
