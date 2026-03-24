#!/bin/bash
# auto-approve-make.sh — Auto-approve common Make targets
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*make\s+(build|test|lint|format|check|clean|install|all|dev|start|run)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"make target auto-approved"}}'
fi
exit 0
