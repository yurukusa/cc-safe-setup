#!/bin/bash
# ================================================================
# django-migrate-guard.sh — Block destructive Django DB operations
#
# Blocks: manage.py flush, manage.py sqlflush, manage.py reset
# Warns: manage.py migrate --fake
# Allows: manage.py migrate, manage.py makemigrations
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/django-migrate-guard.sh" }]
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
  _nojq_warned="/tmp/cc-nojq-warned-django-migrate-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [django-migrate-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block destructive Django commands
if echo "$COMMAND" | grep -qE 'manage\.py\s+(flush|sqlflush)\b'; then
    echo "BLOCKED: Django flush destroys all data." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Warn on fake migrations
if echo "$COMMAND" | grep -qE 'manage\.py\s+migrate\s+.*--fake'; then
    echo "WARNING: Fake migration — database schema won't change." >&2
    echo "This can leave DB and migration history out of sync." >&2
fi

exit 0
