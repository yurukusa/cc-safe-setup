#!/bin/bash
# ================================================================
# prisma-migrate-guard.sh — Block destructive Prisma operations
#
# Blocks: prisma migrate reset, prisma db push --force-reset,
#         prisma db push --accept-data-loss
# Allows: prisma migrate dev, prisma generate, prisma db push (plain)
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
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-prisma-migrate-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [prisma-migrate-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block destructive Prisma commands. --force-reset drops and recreates the
# whole database; --accept-data-loss applies data-destroying schema changes
# without the interactive confirmation — the exact flag that wiped a production
# DB in anthropics/claude-code#14411. Both can sit anywhere after `db push`
# (e.g. after a --schema flag), so match across the rest of the command.
if echo "$COMMAND" | grep -qE 'prisma\s+(migrate\s+reset|db\s+push\b.*(--force-reset|--accept-data-loss))'; then
    echo "BLOCKED: Destructive Prisma command." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "migrate reset / --force-reset / --accept-data-loss destroy data." >&2
    echo "Use: prisma migrate dev (incremental migration)" >&2
    exit 2
fi

# Warn on plain prisma db push (schema push without migration history)
if echo "$COMMAND" | grep -qE 'prisma\s+db\s+push\b' && ! echo "$COMMAND" | grep -qE '\-\-(force-reset|accept-data-loss)'; then
    echo "WARNING: prisma db push skips migration history." >&2
    echo "Consider: prisma migrate dev for tracked migrations." >&2
fi

exit 0
