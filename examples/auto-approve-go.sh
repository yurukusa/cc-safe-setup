#!/bin/bash
# auto-approve-go.sh — Auto-approve Go build/test/vet commands
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*go\s+(build|test|vet|fmt|mod|run|generate|install|clean)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"go command auto-approved"}}'
fi
exit 0
