#!/bin/bash
# auto-approve-gradle.sh — Auto-approve Gradle build/test commands
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '^\s*(gradle|gradlew|./gradlew)\s+(build|test|check|assemble|clean|compileJava|compileKotlin|lint)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"gradle command auto-approved"}}'
fi
exit 0
