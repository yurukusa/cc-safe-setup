#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-laravel-artisan-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [laravel-artisan-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0
if echo "$COMMAND" | grep -qE 'artisan\s+(db:wipe|migrate:fresh|migrate:reset)'; then
    echo "BLOCKED: Destructive Laravel command." >&2
    echo "Command: $COMMAND" >&2
    echo "db:wipe/migrate:fresh destroy all data." >&2
    echo "Use: artisan migrate (incremental)" >&2
    exit 2
fi
exit 0
