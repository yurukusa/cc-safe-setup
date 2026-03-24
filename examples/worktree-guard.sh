#!/bin/bash
# ================================================================
# worktree-guard.sh — Warn when operating in a git worktree
# ================================================================
# PURPOSE:
#   Git worktrees share the same .git directory. Destructive operations
#   in one worktree (git clean, reset) can affect the main working tree.
#   This hook warns when Claude is operating inside a worktree.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check destructive git commands
echo "$COMMAND" | grep -qE '\bgit\s+(clean|reset|checkout\s+--|stash\s+drop)' || exit 0

# Check if we're in a worktree
GITDIR=$(git rev-parse --git-dir 2>/dev/null)
if echo "$GITDIR" | grep -q "worktrees"; then
    MAIN_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/.git$||')
    echo "WARNING: You are in a git worktree." >&2
    echo "Main working tree: $MAIN_DIR" >&2
    echo "Destructive git operations may affect the main tree." >&2
fi

exit 0
