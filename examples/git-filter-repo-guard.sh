#!/bin/bash
# git-filter-repo-guard.sh — Block git history rewriting tools
#
# Solves: Issue #45893 where `git filter-repo --force` destroyed production
#         files by rewriting repository history. These tools permanently
#         alter commit objects and can cause irreversible data loss.
#
# Detects:
#   git filter-repo    (modern history rewriter, any arguments)
#   git filter-branch  (legacy history rewriter, any arguments)
#   bfg                (BFG Repo-Cleaner, third-party history rewriter)
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Block git filter-repo (any arguments)
if echo "$COMMAND" | grep -qE '\bgit\s+filter-repo\b'; then
    echo "BLOCKED: git filter-repo rewrites repository history (see #45893)." >&2
    echo "  This command destroyed production files in a real incident." >&2
    echo "  History rewriting is irreversible and breaks all clones." >&2
    exit 2
fi

# Block git filter-branch (legacy equivalent)
if echo "$COMMAND" | grep -qE '\bgit\s+filter-branch\b'; then
    echo "BLOCKED: git filter-branch rewrites repository history (see #45893)." >&2
    echo "  Legacy history rewriter — same risks as filter-repo." >&2
    echo "  History rewriting is irreversible and breaks all clones." >&2
    exit 2
fi

# Block BFG Repo-Cleaner
if echo "$COMMAND" | grep -qE '\bbfg\b'; then
    echo "BLOCKED: BFG Repo-Cleaner rewrites repository history (see #45893)." >&2
    echo "  Third-party tool with the same risks as git filter-repo." >&2
    echo "  History rewriting is irreversible and breaks all clones." >&2
    exit 2
fi

exit 0
