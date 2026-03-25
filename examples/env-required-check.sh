#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "process\.env\.\w+\s*\|\|" || echo "$CONTENT" | grep -qE "process\.env\.\w+!" && echo "NOTE: Env var without default — add fallback" >&2
exit 0
