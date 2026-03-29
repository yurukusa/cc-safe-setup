#!/bin/bash
# worktree-memory-guard.sh — Warn when memory path resolves to main worktree
#
# Solves: Git worktrees resolving to main worktree's memory directory (#39920).
#         In worktree isolation mode, Claude writes memory to the main repo's
#         .claude/projects/ instead of the worktree's, causing cross-contamination.
#
# How it works: PreToolUse hook on Write/Edit that checks if the target
#   path is a memory file (.claude/projects/*/memory/) and warns if
#   the current working directory differs from the resolved path's repo root.
#
# TRIGGER: PreToolUse
# MATCHER: "Write|Edit"

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check memory files
if ! echo "$FILE" | grep -q '.claude/projects/.*/memory/'; then
  exit 0
fi

# Check if we're in a worktree
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
if [ -z "$GIT_DIR" ]; then
  exit 0
fi

# Detect worktree by checking if .git is a file (worktree) vs directory (main)
if [ -f ".git" ]; then
  # We're in a worktree — check if memory path points to main repo
  MAIN_WORKTREE=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/.git$||')
  CWD=$(pwd)

  if [ "$MAIN_WORKTREE" != "$CWD" ] && echo "$FILE" | grep -q "$MAIN_WORKTREE"; then
    echo "WARNING: Memory file resolves to main worktree, not current worktree." >&2
    echo "  File: $FILE" >&2
    echo "  Main: $MAIN_WORKTREE" >&2
    echo "  CWD:  $CWD" >&2
    echo "  Consider writing to worktree-local memory instead." >&2
  fi
fi

exit 0
