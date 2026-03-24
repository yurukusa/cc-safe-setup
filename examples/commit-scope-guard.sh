#!/bin/bash
# ================================================================
# commit-scope-guard.sh — Warn when committing too many files
# ================================================================
# PURPOSE:
#   Claude Code can modify dozens of files and commit them all at
#   once, making the commit hard to review and revert. This hook
#   warns when staging more than a configurable number of files.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_MAX_COMMIT_FILES=15  (warn above 15 files)
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

MAX="${CC_MAX_COMMIT_FILES:-15}"
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l)

if [ "$STAGED" -gt "$MAX" ]; then
    echo "WARNING: Committing $STAGED files (threshold: $MAX)." >&2
    echo "Consider splitting into smaller, focused commits." >&2
    echo "Files:" >&2
    git diff --cached --name-only 2>/dev/null | head -10 | sed 's/^/  /' >&2
    [ "$STAGED" -gt 10 ] && echo "  ... and $((STAGED-10)) more" >&2
fi

exit 0
