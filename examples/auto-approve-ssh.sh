#!/bin/bash
# auto-approve-ssh.sh — Auto-approve safe SSH commands
#
# Solves: Trailing wildcard in Bash(ssh * cmd *) doesn't match
# when cmd has no arguments.
#
# GitHub Issue: #36873
#
# Usage: Add to settings.json as a PreToolUse hook on "Bash"
# Customize SAFE_COMMANDS for your use case.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Safe remote commands (customize this list)
SAFE_COMMANDS="uptime|w|whoami|hostname|uname|date|df|free|cat /etc/os-release"

if echo "$COMMAND" | grep -qE "^\s*ssh\s+\S+\s+($SAFE_COMMANDS)(\s|$)"; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "safe SSH command auto-approved"
      }
    }'
    exit 0
fi

exit 0
