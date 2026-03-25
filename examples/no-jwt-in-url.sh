#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qiE "token=eyJ|\?jwt=" && echo "WARNING: JWT in URL params" >&2
exit 0
