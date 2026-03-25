#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qiE "createHash\(.*(md5|sha1)" && echo "WARNING: Weak hash (md5/sha1)" >&2
exit 0
