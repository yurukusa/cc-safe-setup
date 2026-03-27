#!/bin/bash
# block-database-wipe.sh — Block destructive database commands
#
# Prevents accidental database destruction from commands like:
#   - Laravel: migrate:fresh, migrate:reset, db:wipe
#   - Django: flush, sqlflush
#   - Rails: db:drop, db:reset
#   - Raw SQL: DROP DATABASE, TRUNCATE
#   - Symfony/Doctrine: fixtures:load (without --append), schema:drop, database:drop
#   - Prisma: migrate reset, db push --force-reset
#   - PostgreSQL: dropdb
#
# Born from GitHub Issues #37405, #37439, #34729, #37574
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/block-database-wipe.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Laravel destructive commands
if echo "$COMMAND" | grep -qiE 'artisan\s+(migrate:fresh|migrate:reset|db:wipe|db:seed\s+--force)'; then
    echo "BLOCKED: Destructive Laravel database command" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Laravel --env flag without corresponding .env file
if echo "$COMMAND" | grep -qE 'artisan.*--env='; then
    ENV_NAME=$(echo "$COMMAND" | grep -oP '(?<=--env=)\w+')
    if [ -n "$ENV_NAME" ] && [ ! -f ".env.$ENV_NAME" ]; then
        echo "BLOCKED: .env.$ENV_NAME does not exist. Command would fall back to .env (possibly production)" >&2
        exit 2
    fi
fi

# Django destructive commands
if echo "$COMMAND" | grep -qiE 'manage\.py\s+(flush|sqlflush)'; then
    echo "BLOCKED: Destructive Django database command" >&2
    exit 2
fi

# Rails destructive commands
if echo "$COMMAND" | grep -qiE 'rake\s+db:(drop|reset)|rails\s+db:(drop|reset)'; then
    echo "BLOCKED: Destructive Rails database command" >&2
    exit 2
fi

# Raw SQL destructive commands
if echo "$COMMAND" | grep -qiE 'DROP\s+(DATABASE|TABLE|SCHEMA)|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\s*(;|\s*$|WHERE\s+(1\s*=\s*1|true))'; then
    echo "BLOCKED: Destructive SQL command" >&2
    exit 2
fi

# Symfony/Doctrine destructive commands
if echo "$COMMAND" | grep -qiE 'doctrine:(fixtures:load|schema:drop|database:drop)' && ! echo "$COMMAND" | grep -qE '\-\-append'; then
    echo "BLOCKED: Destructive Doctrine command (use --append for fixtures:load)" >&2
    exit 2
fi

# Prisma destructive commands
if echo "$COMMAND" | grep -qiE 'prisma\s+migrate\s+reset|prisma\s+db\s+push\s+--force-reset'; then
    echo "BLOCKED: Destructive Prisma database command" >&2
    exit 2
fi

# PostgreSQL CLI
if echo "$COMMAND" | grep -qE '^\s*dropdb\s'; then
    echo "BLOCKED: dropdb command" >&2
    exit 2
fi

exit 0
