#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "cors\(\{.*origin.*true" && echo "NOTE: Permissive CORS config" >&2
exit 0
