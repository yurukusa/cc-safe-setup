#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE "^\s*rm\b"; then COUNT=$(echo "$COMMAND" | tr " " "\n" | grep -cvE "^-" | head -1); [ "$COUNT" -gt 5 ] && echo "WARNING: Deleting $COUNT files at once" >&2; fi
exit 0
