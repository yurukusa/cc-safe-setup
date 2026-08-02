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
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-git-crypt-worktree-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [git-crypt-worktree-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
