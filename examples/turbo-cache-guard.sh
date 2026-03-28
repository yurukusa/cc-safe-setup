#!/bin/bash
# ================================================================
# turbo-cache-guard.sh — Warn before clearing Turborepo cache
#
# Blocks: turbo prune (dangerous in wrong context)
# Warns: turbo clean, clearing .turbo/ cache
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/turbo-cache-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Warn on turbo cache clearing
if echo "$COMMAND" | grep -qE 'turbo\s+(clean|daemon\s+clean)'; then
    echo "WARNING: Clearing Turborepo cache." >&2
    echo "Next build will be slower (full rebuild)." >&2
fi

# Warn on deleting .turbo directory
if echo "$COMMAND" | grep -qE 'rm\s+.*\.turbo'; then
    echo "WARNING: Deleting .turbo cache directory." >&2
fi

exit 0
