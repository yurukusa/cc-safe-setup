#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\brm\b.*package\.json'; then
    echo "BLOCKED: Deleting package.json" >&2; exit 2
fi
exit 0
