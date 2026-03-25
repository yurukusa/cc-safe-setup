#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE 'git\s+tag\s+(-a\s+|-d\s+)?v'; then
    echo "WARNING: Creating git tag. Verify version number." >&2
fi
if echo "$COMMAND" | grep -qE 'git\s+push.*--tags'; then
    echo "BLOCKED: Pushing all tags. Push specific tags instead." >&2
    exit 2
fi
exit 0
