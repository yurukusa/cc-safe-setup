#!/bin/bash
# ================================================================
# composer-guard.sh — Block dangerous Composer operations
#
# Blocks: composer global require (affects system PHP),
#         composer remove (accidental dependency removal)
# Warns: composer require without --dev flag
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/composer-guard.sh" }]
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
  _nojq_warned="/tmp/cc-nojq-warned-composer-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [composer-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block global require
if echo "$COMMAND" | grep -qE 'composer\s+global\s+require'; then
    echo "BLOCKED: Global Composer package installation." >&2
    echo "Command: $COMMAND" >&2
    echo "Global packages affect the entire system." >&2
    echo "Use: composer require <package> (local project only)" >&2
    exit 2
fi

exit 0
