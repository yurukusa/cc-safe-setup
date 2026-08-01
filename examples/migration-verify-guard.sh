#!/bin/bash
# migration-verify-guard.sh — Require verification before destructive migrations
#
# Solves: Claude executing destructive database/code migrations without
#         verifying the plan first (#35435). A Rust migration went wrong
#         across 2 sessions with 20 compounding errors.
#
# How it works: PreToolUse hook on Bash that detects migration commands
#   and blocks them unless a verification marker file exists.
#   Create the marker: touch .claude/migration-approved
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-migration-verify-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [migration-verify-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect migration commands across frameworks
MIGRATION_PATTERN='(migrate|migration|db:migrate|typeorm.*migration|prisma.*migrate|alembic|flyway|liquibase|knex.*migrate|sequelize.*db:migrate|rails.*db:migrate|django.*migrate|drizzle.*push)'

if echo "$COMMAND" | grep -qiE "$MIGRATION_PATTERN"; then
  # Check for approval marker
  if [ -f ".claude/migration-approved" ]; then
    # Consume the marker (one-time use)
    rm -f ".claude/migration-approved"
    exit 0
  fi

  echo "BLOCKED: Migration command detected without verification." >&2
  echo "" >&2
  echo "Command: $COMMAND" >&2
  echo "" >&2
  echo "Before running migrations:" >&2
  echo "  1. Review the migration plan carefully" >&2
  echo "  2. Ensure you have a backup or can rollback" >&2
  echo "  3. Create approval: touch .claude/migration-approved" >&2
  echo "  4. Then retry the command" >&2
  exit 2
fi

exit 0
