#!/bin/bash
# git-checkout-safety-guard.sh — Prevent file loss from careless branch switching
#
# Solves: git checkout to another branch removes files that only exist
#         on the current branch, causing data loss (#37150)
#
# The pattern:
#   1. User works on feature branch with new files
#   2. Agent runs "git checkout master" — files disappear from working tree
#   3. Agent runs "git branch -D feature" — files unrecoverable
#
# This hook blocks git checkout/switch when:
#   - There are uncommitted changes (safety baseline)
#   - The command includes branch deletion (-D, -d) of a non-merged branch
#
# Usage: PreToolUse hook on "Bash"
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/git-checkout-safety-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# === Check 1: git checkout/switch to different branch with uncommitted changes ===
if echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)\s+[a-zA-Z]'; then
    # Check for uncommitted changes
    if git status --porcelain 2>/dev/null | grep -q '^'; then
        echo "BLOCKED: git checkout with uncommitted changes" >&2
        echo "  Commit or stash your changes first to avoid data loss." >&2
        exit 2
    fi
fi

# === Check 2: git branch -D (force delete) ===
if echo "$COMMAND" | grep -qE 'git\s+branch\s+-[dD]\s'; then
    BRANCH=$(echo "$COMMAND" | grep -oE 'git\s+branch\s+-[dD]\s+(\S+)' | awk '{print $NF}')
    echo "BLOCKED: Destructive branch deletion: $BRANCH" >&2
    echo "  Use 'git branch -d' (lowercase) for safe deletion (checks merge status)." >&2
    echo "  Force deletion (-D) can cause unrecoverable data loss." >&2
    exit 2
fi

# === Check 3: git checkout -- . (discard all changes) ===
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+\.'; then
    echo "BLOCKED: git checkout -- . discards ALL uncommitted changes" >&2
    echo "  Use 'git stash' to save changes, or specify individual files." >&2
    exit 2
fi

# === Check 4: git checkout + branch -D in same command (the #37150 pattern) ===
if echo "$COMMAND" | grep -qE 'git\s+checkout.*&&.*git\s+branch\s+-D'; then
    echo "BLOCKED: checkout + branch deletion is a data loss pattern" >&2
    echo "  Files that only exist on the deleted branch will be lost forever." >&2
    exit 2
fi

exit 0
