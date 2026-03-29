#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\b(npm|pip|yarn)\s+install\s+.*--force'; then
    echo "WARNING: --force install bypasses dependency checks." >&2
    echo "Fix the underlying issue instead." >&2
fi
exit 0
