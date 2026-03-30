#!/bin/bash
# git-crypt-worktree-guard.sh — Block worktree creation in git-crypt repos
#
# Solves: When Claude creates a worktree in a git-crypt repo,
#         the smudge filter fails because git-crypt hasn't been
#         unlocked in the new worktree. This produces destructive
#         commits that delete all encrypted files (#38538).
#
# How it works: Before git worktree add, checks if the repo
#   uses git-crypt (.gitattributes contains filter=git-crypt).
#   If yes, blocks the worktree creation with a warning.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail
INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git worktree add
if ! echo "$COMMAND" | grep -qE 'git\s+worktree\s+add'; then
  exit 0
fi

# Check if repo uses git-crypt
if [ -f ".gitattributes" ] && grep -q "filter=git-crypt" .gitattributes 2>/dev/null; then
  echo "BLOCKED: Cannot create worktree in a git-crypt repo." >&2
  echo "git-crypt is not automatically unlocked in new worktrees." >&2
  echo "This would produce destructive commits that delete all encrypted files." >&2
  echo "Work in the main repo instead, or manually run 'git-crypt unlock' in the worktree first." >&2
  exit 2
fi

exit 0
