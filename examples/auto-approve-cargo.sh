#!/bin/bash
# auto-approve-cargo.sh — Auto-approve Rust cargo commands
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*cargo\s+(build|test|check|clippy|fmt|run|bench|doc|clean)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"cargo command auto-approved"}}'
fi
exit 0
