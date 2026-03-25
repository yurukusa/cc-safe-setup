#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "npm\s+install\s+\S+@[0-9]" && echo "$COMMAND" | grep -qE "@[0-1]\."; then echo "WARNING: Possible package downgrade" >&2; fi
exit 0
