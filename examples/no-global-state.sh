#!/bin/bash
CONTENT=$(cat | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0
echo "$CONTENT" | grep -qE "^(let|var)\s+\w+\s*=" && echo "NOTE: Module-level mutable state — consider encapsulation" >&2
exit 0
