#!/bin/bash
# git-config-guard.sh — Block git config --global modifications
#
# Solves: Claude modifying global git config (user.email, user.name)
# without user consent (#37201)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/git-config-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block git config --global (any subcommand)
if echo "$COMMAND" | grep -qE '\bgit\s+config\s+--global\b'; then
    echo "BLOCKED: git config --global is not allowed" >&2
    echo "Use --local for project-specific config instead" >&2
    exit 2
fi

# Block git config --system
if echo "$COMMAND" | grep -qE '\bgit\s+config\s+--system\b'; then
    echo "BLOCKED: git config --system is not allowed" >&2
    exit 2
fi

exit 0
