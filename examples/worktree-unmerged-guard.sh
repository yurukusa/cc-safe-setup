#!/bin/bash
# worktree-unmerged-guard.sh — Prevent worktree cleanup with unmerged commits
#
# Solves: Worktree sessions silently delete branches with unmerged/unpushed commits
#         (#38287 — lost commits recoverable only via git fsck)
#
# How it works: Checks for unmerged commits before worktree removal.
#               If the worktree branch has commits not in main/master, blocks cleanup.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/worktree-unmerged-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
# jq with python3 fallback (macOS may not have jq)
if command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
    COMMAND=$(echo "$INPUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)
fi

[ -z "$COMMAND" ] && exit 0

# Detect worktree removal commands
if ! echo "$COMMAND" | grep -qE 'git\s+worktree\s+(remove|prune)|rm\s+.*worktree'; then
    exit 0
fi

# Extract worktree path
WORKTREE_PATH=$(echo "$COMMAND" | grep -oP 'git\s+worktree\s+remove\s+\K[^\s]+')

if [ -z "$WORKTREE_PATH" ]; then
    # Maybe it's rm -rf on a worktree directory
    exit 0
fi

# Check if the worktree exists and has a branch
if [ ! -d "$WORKTREE_PATH" ]; then
    exit 0
fi

# Get the branch name for this worktree
BRANCH=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
    exit 0
fi

# Find the default branch (portable: checks symbolic ref, then tries main/master)
DEFAULT_BRANCH=$(git -C "$WORKTREE_PATH" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "$DEFAULT_BRANCH" ]; then
    for candidate in main master; do
        git -C "$WORKTREE_PATH" rev-parse --verify "$candidate" &>/dev/null && DEFAULT_BRANCH="$candidate" && break
    done
fi
[ -z "$DEFAULT_BRANCH" ] && exit 0

# Count unmerged commits
UNMERGED=$(git -C "$WORKTREE_PATH" log --oneline "$DEFAULT_BRANCH..$BRANCH" 2>/dev/null | wc -l)

if [ "$UNMERGED" -gt 0 ]; then
    echo "BLOCKED: Worktree branch '$BRANCH' has $UNMERGED unmerged commit(s)" >&2
    echo "Merge or push the branch before removing the worktree:" >&2
    echo "  git -C $WORKTREE_PATH push origin $BRANCH" >&2
    echo "  # or: git merge $BRANCH" >&2
    exit 2
fi

# Check for unpushed commits
UNPUSHED=$(git -C "$WORKTREE_PATH" log --oneline "origin/$BRANCH..$BRANCH" 2>/dev/null | wc -l)

if [ "$UNPUSHED" -gt 0 ]; then
    echo "BLOCKED: Worktree branch '$BRANCH' has $UNPUSHED unpushed commit(s)" >&2
    echo "Push before removing: git -C $WORKTREE_PATH push origin $BRANCH" >&2
    exit 2
fi

exit 0
