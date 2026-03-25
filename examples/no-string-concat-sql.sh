#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qiE "\"SELECT.*\+|'SELECT.*\+" && echo "WARNING: String concatenation in SQL — use parameterized queries" >&2
exit 0
