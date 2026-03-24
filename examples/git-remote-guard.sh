#!/bin/bash
# ================================================================
# git-remote-guard.sh — Block push/fetch to unknown git remotes
# ================================================================
# PURPOSE:
#   Claude might add a new git remote and push code to it.
#   This hook warns when git push/fetch targets a remote that
#   wasn't in the original repo configuration.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check for git remote add
if echo "$COMMAND" | grep -qE '\bgit\s+remote\s+add\b'; then
    echo "WARNING: Adding a new git remote." >&2
    echo "Command: $COMMAND" >&2
    echo "Verify this is a trusted repository." >&2
fi

# Check for push to non-origin remote
if echo "$COMMAND" | grep -qE '\bgit\s+push\s+(?!origin\b)\w'; then
    REMOTE=$(echo "$COMMAND" | grep -oE 'git\s+push\s+(\S+)' | awk '{print $3}')
    if [ -n "$REMOTE" ] && [ "$REMOTE" != "origin" ]; then
        echo "WARNING: Pushing to non-origin remote: $REMOTE" >&2
        echo "Verify this remote is trusted." >&2
    fi
fi

exit 0
