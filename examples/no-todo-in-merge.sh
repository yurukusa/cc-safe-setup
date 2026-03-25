#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
COMMAND=$(cat | jq -r ".tool_input.command // empty" 2>/dev/null); echo "$COMMAND" | grep -qE "git\s+merge" && git diff --cached 2>/dev/null | grep -q "TODO" && echo "WARNING: TODO markers in merge target" >&2
exit 0
