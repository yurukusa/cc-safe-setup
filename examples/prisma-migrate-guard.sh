#!/bin/bash
# ================================================================
# prisma-migrate-guard.sh — Block destructive Prisma operations
#
# Blocks: prisma migrate reset, prisma db push --force-reset
# Allows: prisma migrate dev, prisma generate, prisma db push
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/prisma-migrate-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block destructive Prisma commands
if echo "$COMMAND" | grep -qE 'prisma\s+(migrate\s+reset|db\s+push\s+--force-reset)'; then
    echo "BLOCKED: Destructive Prisma command." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "migrate reset / force-reset destroy all data." >&2
    echo "Use: prisma migrate dev (incremental migration)" >&2
    exit 2
fi

# Warn on prisma db push (schema push without migration history)
if echo "$COMMAND" | grep -qE 'prisma\s+db\s+push\b' && ! echo "$COMMAND" | grep -q "\-\-force-reset"; then
    echo "WARNING: prisma db push skips migration history." >&2
    echo "Consider: prisma migrate dev for tracked migrations." >&2
fi

exit 0
