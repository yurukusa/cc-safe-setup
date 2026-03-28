#!/bin/bash
# db-connect-guard.sh — Warn on direct database connections
#
# Solves: Claude Code connecting to databases directly via CLI clients
#         and running queries without understanding the environment.
#         Production database connections should go through application
#         code, not direct CLI access.
#
# Real incidents:
#   #36183 — prisma db push --force-reset on production
#   #33183 — prisma db push against production database
#   #27063 — destructive db command wiped production
#
# Detects:
#   mysql -h <host>          (MySQL direct connection)
#   psql -h <host>           (PostgreSQL direct connection)
#   mongo <connection-string> (MongoDB direct connection)
#   redis-cli -h <host>      (Redis direct connection)
#   prisma db push           (Prisma schema push)
#   prisma migrate deploy    (Prisma migration)
#
# Does NOT block:
#   mysql (local, no -h flag — likely development)
#   psql (local connection)
#   prisma generate (code generation, not DB change)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block remote database connections
if echo "$COMMAND" | grep -qE '\b(mysql|psql|mongosh?)\s+.*(-h\s+|--host[= ])'; then
    echo "BLOCKED: Direct remote database connection detected." >&2
    echo "  Remote DB connections should use application code, not CLI." >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

# Block redis remote connections
if echo "$COMMAND" | grep -qE '\bredis-cli\s+.*(-h\s+|--host)'; then
    echo "BLOCKED: Direct remote Redis connection detected." >&2
    exit 2
fi

# Block Prisma destructive operations
if echo "$COMMAND" | grep -qE '\bprisma\s+(db\s+push|migrate\s+deploy|migrate\s+reset)'; then
    echo "BLOCKED: Prisma database modification detected." >&2
    echo "  prisma db push/migrate can destroy production data." >&2
    echo "  Verify DATABASE_URL points to the correct environment." >&2
    exit 2
fi

exit 0
