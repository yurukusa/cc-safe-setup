#!/bin/bash
# ================================================================
# drizzle-migrate-guard.sh — Block destructive Drizzle ORM operations
#
# Blocks: drizzle-kit drop, drizzle-kit push with --force
# Allows: drizzle-kit generate, drizzle-kit migrate
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash|PowerShell",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/drizzle-migrate-guard.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash|PowerShell"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-drizzle-migrate-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [drizzle-migrate-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block destructive Drizzle commands
if echo "$COMMAND" | grep -qE 'drizzle-kit\s+drop'; then
    echo "BLOCKED: drizzle-kit drop destroys migration files." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Block 'drizzle-kit push --force'. Plain 'push' prompts before any data-loss
# change; --force (and the legacy push:pg/push:mysql/push:sqlite variants)
# skips that prompt and applies the change directly — the exact way autonomous
# agents have wiped production databases (anthropics/claude-code#27063, and the
# sibling prisma case #36183). The header has always advertised this block; it
# was never implemented, so a user relying on this hook was unprotected.
if echo "$COMMAND" | grep -qE 'drizzle-kit\s+push(:[a-z]+)?\b' && echo "$COMMAND" | grep -qE '\-\-force(-reset)?\b'; then
    echo "BLOCKED: 'drizzle-kit push --force' applies schema changes without the data-loss prompt and can wipe table data." >&2
    echo "Command: $COMMAND" >&2
    echo "Use 'drizzle-kit generate' + 'drizzle-kit migrate' for a reviewable migration, or drop --force to keep the interactive guard." >&2
    exit 2
fi

exit 0
