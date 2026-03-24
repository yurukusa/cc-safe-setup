#!/bin/bash
# ================================================================
# git-author-guard.sh — Verify commit author is configured correctly
# ================================================================
# PURPOSE:
#   Claude Code sometimes commits with incorrect or default
#   git author settings. This hook checks that user.name and
#   user.email are set before allowing commits.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

NAME=$(git config user.name 2>/dev/null)
EMAIL=$(git config user.email 2>/dev/null)

if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then
    echo "WARNING: Git author not configured." >&2
    [ -z "$NAME" ] && echo "  Missing: git config user.name" >&2
    [ -z "$EMAIL" ] && echo "  Missing: git config user.email" >&2
fi

# Warn on common placeholder values
if echo "$EMAIL" | grep -qE '(example\.com|noreply|placeholder)' 2>/dev/null; then
    echo "WARNING: Git email looks like a placeholder: $EMAIL" >&2
fi

exit 0
