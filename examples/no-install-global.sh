#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE 'npm\s+install\s+-g\s|npm\s+i\s+-g\s'; then
    echo "BLOCKED: Global npm install. Use npx or local install." >&2
    exit 2
fi
if echo "$COMMAND" | grep -qE 'sudo\s+pip\s+install|pip\s+install\s+--system'; then
    echo "BLOCKED: System-wide pip install. Use virtualenv." >&2
    exit 2
fi
exit 0
