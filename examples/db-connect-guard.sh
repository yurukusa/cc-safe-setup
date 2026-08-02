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
# TRIGGER: PreToolUse  MATCHER: "Bash|PowerShell"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-db-connect-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [db-connect-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block remote database connections
if echo "$COMMAND" | grep -qE '\b(mysql|psql|mongo(sh)?)\s+.*(-h\s+|--host[= ])'; then
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
