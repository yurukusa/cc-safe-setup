#!/bin/bash
# block-database-wipe.sh — Block destructive database commands
#
# Prevents accidental database destruction from commands like:
#   - Laravel: migrate:fresh, migrate:refresh, migrate:reset, db:wipe
#   - Django: flush, sqlflush, migrate <app> zero
#   - Rails: db:drop, db:reset, db:schema:load
#   - Raw SQL: DROP DATABASE, TRUNCATE
#   - Symfony/Doctrine: fixtures:load (without --append), schema:drop, database:drop
#   - Prisma: migrate reset, db push --force-reset
#   - TypeORM/Sequelize: schema:drop, db:drop
#   - PostgreSQL: dropdb
#
# Born from GitHub Issues #37405, #37439, #34729, #37574, #69059
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
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-block-database-wipe-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [block-database-wipe]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Laravel destructive commands
if echo "$COMMAND" | grep -qiE 'artisan\s+(migrate:fresh|migrate:refresh|migrate:reset|db:wipe|db:seed\s+--force)'; then
    echo "BLOCKED: Destructive Laravel database command" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Laravel --env flag without corresponding .env file
if echo "$COMMAND" | grep -qE 'artisan.*--env='; then
    # -P は GNU 拡張。BSD grep では ENV_NAME が空になり、下の「.env.<名前> が無い」検査だけが
    # 静かに消える（この入力では別の exit 2 が先に止めるので結果は変わらないが、検査は消えている）。
    # 後読み (?<=…) の代わりに、-- 以降を切り出して前置きを落とす。
    ENV_NAME=$(echo "$COMMAND" | grep -oE '\-\-env=[A-Za-z0-9_]+' | sed -E 's/^--env=//')
    if [ -n "$ENV_NAME" ] && [ ! -f ".env.$ENV_NAME" ]; then
        echo "BLOCKED: .env.$ENV_NAME does not exist. Command would fall back to .env (possibly production)" >&2
        exit 2
    fi
fi

# Django destructive commands (flush wipes data; "migrate <app> zero" unapplies all
# migrations for an app, dropping its tables)
if echo "$COMMAND" | grep -qiE 'manage\.py\s+(flush|sqlflush)' \
   || echo "$COMMAND" | grep -qiE 'manage\.py\s+migrate\s+\w+\s+zero'; then
    echo "BLOCKED: Destructive Django database command" >&2
    exit 2
fi

# Rails destructive commands (db:schema:load drops and recreates every table from schema.rb)
if echo "$COMMAND" | grep -qiE '(rake|rails)\s+db:(drop|reset|schema:load)'; then
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

# TypeORM / Sequelize destructive commands
# typeorm "schema:drop" drops the whole schema; sequelize(-cli) "db:drop" drops the database
if echo "$COMMAND" | grep -qiE 'typeorm\s+schema:drop|sequelize(-cli)?\s+db:drop'; then
    echo "BLOCKED: Destructive TypeORM/Sequelize database command" >&2
    exit 2
fi

# PostgreSQL CLI
if echo "$COMMAND" | grep -qE '^\s*dropdb\s'; then
    echo "BLOCKED: dropdb command" >&2
    exit 2
fi

exit 0
