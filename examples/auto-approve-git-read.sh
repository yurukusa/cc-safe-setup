#!/bin/bash
# auto-approve-git-read.sh — Auto-approve read-only git commands
#
# Solves: Permission prompts for git status, git log, git diff
# even when using "allow" rules (Claude adds -C flags that
# break pattern matching).
#
# GitHub Issues: #36900, #32985
#
# Usage: Add to settings.json as a PreToolUse hook on "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Match git read-only commands with optional -C flag
if echo "$COMMAND" | grep -qE '^\s*git\s+(-C\s+\S+\s+)?(status|log|diff|branch|show|rev-parse|tag|remote)(\s|$)'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "git read-only auto-approved"
      }
    }'
    exit 0
fi

# Match cd + git read-only compounds
if echo "$COMMAND" | grep -qE '^\s*cd\s+.*&&\s*git\s+(status|log|diff|branch|show|rev-parse)'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "cd+git compound auto-approved"
      }
    }'
    exit 0
fi

exit 0
