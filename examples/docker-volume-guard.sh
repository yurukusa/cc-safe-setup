#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bdocker\s+volume\s+(rm|prune)\b'; then
    echo "WARNING: Docker volume deletion detected." >&2
    echo "Volumes may contain persistent data." >&2
fi
exit 0
