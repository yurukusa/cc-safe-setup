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
