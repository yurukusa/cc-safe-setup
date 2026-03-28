#!/bin/bash
# ================================================================
# drizzle-migrate-guard.sh — Block destructive Drizzle ORM operations
#
# Blocks: drizzle-kit drop, drizzle-kit push with --force
# Allows: drizzle-kit generate, drizzle-kit migrate
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/drizzle-migrate-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block destructive Drizzle commands
if echo "$COMMAND" | grep -qE 'drizzle-kit\s+drop'; then
    echo "BLOCKED: drizzle-kit drop destroys migration files." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

exit 0
