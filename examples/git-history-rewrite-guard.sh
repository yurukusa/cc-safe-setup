#!/bin/bash
# git-history-rewrite-guard.sh — Block git history rewriting commands
#
# Solves: Claude Code rewriting git history which can cause permanent
#         data loss and break shared branches. History rewriting on
#         pushed commits requires force-push and affects all collaborators.
#
# Detects:
#   git filter-branch           (legacy history rewriter)
#   git filter-repo             (modern history rewriter)
#   git rebase -i               (interactive rebase, can reorder/squash)
#   git reset --hard HEAD~N     (discards recent commits)
#   git reflog expire --all     (destroys reflog recovery data)
#
# Does NOT block:
#   git rebase <branch>         (non-interactive, covered by no-git-rebase-public)
#   git reset --soft            (safe, keeps changes staged)
#   git reset --mixed           (safe, keeps changes in working tree)
#   git reflog                  (read-only, viewing history)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block filter-branch (legacy, dangerous)
if echo "$COMMAND" | grep -qE '\bgit\s+filter-branch\b'; then
    echo "BLOCKED: git filter-branch rewrites entire repository history." >&2
    echo "  This is irreversible on shared branches." >&2
    exit 2
fi

# Block filter-repo
if echo "$COMMAND" | grep -qE '\bgit\s+filter-repo\b'; then
    echo "BLOCKED: git filter-repo rewrites repository history." >&2
    exit 2
fi

# Block interactive rebase
if echo "$COMMAND" | grep -qE '\bgit\s+rebase\s+-i\b'; then
    echo "BLOCKED: Interactive rebase can reorder, squash, or drop commits." >&2
    echo "  Use non-interactive rebase instead." >&2
    exit 2
fi

# Block git reset --hard with commit count
if echo "$COMMAND" | grep -qE '\bgit\s+reset\s+--hard\s+(HEAD|origin)'; then
    echo "BLOCKED: git reset --hard discards commits permanently." >&2
    echo "  Use 'git reset --soft' to keep changes staged." >&2
    exit 2
fi

# Block reflog destruction
if echo "$COMMAND" | grep -qE '\bgit\s+reflog\s+(expire|delete)\b'; then
    echo "BLOCKED: Destroying reflog removes the safety net for recovering commits." >&2
    exit 2
fi

exit 0
