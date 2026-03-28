#!/bin/bash
# ================================================================
# rails-migration-guard.sh — Block destructive Rails migrations
#
# Blocks: rails db:drop, rails db:reset, rails db:migrate:reset
# Allows: rails db:migrate, rails db:seed, rails db:create
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/rails-migration-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block destructive Rails database commands
if echo "$COMMAND" | grep -qE 'rails\s+db:(drop|reset|migrate:reset|purge|schema:load)'; then
    echo "BLOCKED: Destructive Rails database command." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "db:drop/reset/purge destroy all data." >&2
    echo "Use db:migrate for incremental changes." >&2
    exit 2
fi

# Block rake equivalents
if echo "$COMMAND" | grep -qE 'rake\s+db:(drop|reset|migrate:reset|purge)'; then
    echo "BLOCKED: Destructive rake database command." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

exit 0
