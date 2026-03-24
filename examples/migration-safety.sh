#!/bin/bash
# migration-safety.sh — Require backup before database migrations
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qiE '\b(migrate|migration|alembic|knex|sequelize.*migrate|flyway)\b'; then
    if ! echo "$COMMAND" | grep -qiE '(status|list|pending|--dry-run|--check)'; then
        echo "WARNING: Database migration detected." >&2
        echo "Ensure you have a backup before running migrations." >&2
    fi
fi
exit 0
