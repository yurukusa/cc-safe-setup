#!/bin/bash
# worktree-path-validator.sh — Warn when file operations target main workspace instead of worktree
#
# Solves: In worktree sessions, Edit/Read/Write tools target
#         files in the main workspace instead of the worktree
#         directory (#36182). This causes edits to the wrong
#         copy of files.
#
# How it works: Detects if running in a worktree (git rev-parse
#   --git-common-dir differs from --git-dir). If so, checks
#   that file_path targets the worktree, not the main workspace.
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write|Read"

set -euo pipefail
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && exit 0

# Check if we're in a worktree
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0

# If git-dir == git-common-dir, we're in the main repo (not a worktree)
[ "$GIT_DIR" = "$GIT_COMMON" ] && exit 0

# We're in a worktree — check that file_path is within the worktree
WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
MAIN_ROOT=$(cd "$GIT_COMMON/.." && pwd 2>/dev/null) || exit 0

# If file_path starts with the main workspace path instead of worktree
if echo "$FILE_PATH" | grep -q "^$MAIN_ROOT" && ! echo "$FILE_PATH" | grep -q "^$WORKTREE_ROOT"; then
  echo "WARNING: File path targets main workspace, not this worktree." >&2
  echo "  File: $FILE_PATH" >&2
  echo "  Worktree: $WORKTREE_ROOT" >&2
  echo "  Main repo: $MAIN_ROOT" >&2
  echo "  Consider using: ${FILE_PATH/$MAIN_ROOT/$WORKTREE_ROOT}" >&2
fi

exit 0
