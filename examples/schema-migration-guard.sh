#!/bin/bash
# schema-migration-guard.sh — Warn on database schema migrations without backup
#
# Solves: Claude running destructive schema migrations (DROP COLUMN,
#         ALTER TABLE, DROP INDEX) without first creating a backup or
#         generating a rollback migration.
#
# How it works: PreToolUse hook on Bash that detects migration commands
#   (Rails, Django, Prisma, Flyway, Liquibase, raw SQL) and warns if
#   they contain destructive operations.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect migration commands
IS_MIGRATION=false
case "$COMMAND" in
    *"migrate"*|*"migration"*|*"db:migrate"*|*"prisma migrate"*|*"alembic"*|*"flyway"*|*"liquibase"*)
        IS_MIGRATION=true ;;
esac

# Also check for raw SQL with destructive operations
if echo "$COMMAND" | grep -qEi '(DROP\s+(TABLE|COLUMN|INDEX|DATABASE|SCHEMA)|ALTER\s+TABLE.*DROP|TRUNCATE\s+TABLE|DELETE\s+FROM.*WHERE\s+1)'; then
    IS_MIGRATION=true
fi

$IS_MIGRATION || exit 0

# Check for destructive patterns
DESTRUCT=""
if echo "$COMMAND" | grep -qEi 'DROP\s+(TABLE|COLUMN|INDEX|DATABASE)'; then
    DESTRUCT="${DESTRUCT}DROP operation detected. "
fi
if echo "$COMMAND" | grep -qEi 'TRUNCATE'; then
    DESTRUCT="${DESTRUCT}TRUNCATE detected. "
fi
if echo "$COMMAND" | grep -qEi -- '--force|--no-check|--skip-validation'; then
    DESTRUCT="${DESTRUCT}Safety bypass flag detected. "
fi

if [ -n "$DESTRUCT" ]; then
    echo "WARNING: Destructive database migration detected." >&2
    echo "  Command: $COMMAND" >&2
    echo "  Issues: $DESTRUCT" >&2
    echo "  Before running:" >&2
    echo "    1. Create a database backup" >&2
    echo "    2. Generate a rollback migration" >&2
    echo "    3. Test on staging first" >&2
fi

exit 0
