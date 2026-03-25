#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
COMMAND=$(cat | jq -r ".tool_input.command // empty" 2>/dev/null); echo "$COMMAND" | grep -qE "npm\s+install\s+\w" && echo "NOTE: Check dependency license before adding" >&2
exit 0
