#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
COMMAND=$(cat | jq -r ".tool_input.command // empty" 2>/dev/null); echo "$COMMAND" | grep -qE "git\s+commit" && [ ! -f "README.md" ] && echo "NOTE: No README.md in project" >&2
exit 0
