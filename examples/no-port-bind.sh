#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '(--port|--listen|-p\s+\d|0\.0\.0\.0|INADDR_ANY|nc\s+-l)'; then
    echo "WARNING: Command may bind to a network port." >&2
    echo "Command: $COMMAND" >&2
fi
exit 0
