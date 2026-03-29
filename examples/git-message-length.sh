#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE "git\s+commit\s+-m" || exit 0; MSG=$(echo "$COMMAND" | grep -oP "(?<=-m\s[\x27\x22])[^\x27\x22]+"); [ ${#MSG} -lt 10 ] && echo "WARNING: Commit message too short (${#MSG} chars)" >&2
exit 0
