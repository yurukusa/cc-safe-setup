#!/bin/bash
# env-var-check.sh — Warn when setting environment variables with secrets
#
# Solves: Claude hardcoding API keys or passwords into export commands
# that end up in shell history and process environment.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/env-var-check.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Check for export/set with sensitive-looking values
if echo "$COMMAND" | grep -qiE 'export\s+(API_KEY|SECRET|TOKEN|PASSWORD|CREDENTIALS|AUTH)='; then
    echo "" >&2
    echo "⚠ SECURITY: Setting sensitive environment variable in shell" >&2
    echo "This will appear in shell history. Use .env files or secret managers instead." >&2
    echo "Command: $COMMAND" >&2
fi

# Check for hardcoded key patterns (sk-, pk-, ghp_, etc.)
if echo "$COMMAND" | grep -qE 'export\s+\w+=.*(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|glpat-[a-zA-Z0-9]{20,})'; then
    echo "BLOCKED: Hardcoded API key detected in export command" >&2
    echo "Use: export VAR=\$(cat ~/.credentials/key)" >&2
    exit 2
fi

exit 0
