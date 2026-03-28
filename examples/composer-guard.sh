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
