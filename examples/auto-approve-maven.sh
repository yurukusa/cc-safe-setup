#!/bin/bash
# auto-approve-maven.sh — Auto-approve Maven build/test commands
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*(mvn|mvnw|./mvnw)\s+(compile|test|verify|package|clean|install)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"maven command auto-approved"}}'
fi
exit 0
