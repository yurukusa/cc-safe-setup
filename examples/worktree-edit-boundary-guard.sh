#!/bin/bash
# worktree-edit-boundary-guard.sh — Warn or block when Edit/Write/NotebookEdit
# targets a path outside the active git worktree boundary.
#
# Solves: anthropics/claude-code#59628 — Claude Code sessions launched inside
# a git worktree receive a system-prompt declaration ("you are operating in a
# git worktree") but the harness does NOT prevent Edit/Write/NotebookEdit calls
# whose resolved absolute path points into the parent main checkout. An agent
# using cd-style context or absolute paths can dirty the main branch's working
# tree without prompt, warning, or confirmation. The worktree boundary is a
# claim in the system prompt; it is not an enforced isolation at the tool layer.
#
# This hook closes that gap from the operator side: when the current working
# directory is inside a worktree (detected via `git rev-parse --git-common-dir`
# differing from `git rev-parse --git-dir`), and the target file_path resolves
# outside the worktree's working tree, emit a warning (default) or block (opt-in
# via env). Pass-through outside worktrees, outside repos, or when target path
# is inside the worktree.
#
# Configuration:
#   CC_WORKTREE_BOUNDARY_MODE=warn (default)  — emit stderr, exit 0 (advisory)
#   CC_WORKTREE_BOUNDARY_MODE=block          — emit stderr, exit 2 (block)
#   CC_WORKTREE_BOUNDARY_QUIET=1              — suppress all output (still exits)
#
# Usage: settings.json PreToolUse hook with matcher "Edit|Write|NotebookEdit".
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write|NotebookEdit"

set -u

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-worktree-edit-boundary-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [worktree-edit-boundary-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only edit-style tools
case "$TOOL" in
    Edit|Write|NotebookEdit) ;;
    *) exit 0 ;;
esac

[ -z "$FILE" ] && exit 0

# Detect worktree: git-dir vs git-common-dir
# In a worktree, git-dir points to .git/worktrees/<name>, git-common-dir to the main .git
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0

# Resolve both to absolute paths for comparison
GIT_DIR_ABS=$(cd "$GIT_DIR" 2>/dev/null && pwd -P) || exit 0
GIT_COMMON_ABS=$(cd "$GIT_COMMON" 2>/dev/null && pwd -P) || exit 0

# Not a worktree if git-dir == git-common-dir
[ "$GIT_DIR_ABS" = "$GIT_COMMON_ABS" ] && exit 0

# We are in a worktree. Determine the worktree boundary (top of working tree).
WORKTREE_TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
WORKTREE_TOP_ABS=$(cd "$WORKTREE_TOP" 2>/dev/null && pwd -P) || exit 0

# Resolve target path. If relative, anchor to current working directory.
# We do NOT require the file to exist (Write may create new files).
if [[ "$FILE" = /* ]]; then
    TARGET="$FILE"
else
    TARGET="$PWD/$FILE"
fi

# Normalize: resolve .. and . segments without requiring the path to exist.
# Use python if available for portability, otherwise fall back to readlink -m.
if command -v python3 >/dev/null 2>&1; then
    TARGET_ABS=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$TARGET" 2>/dev/null)
elif command -v readlink >/dev/null 2>&1 && readlink -m / >/dev/null 2>&1; then
    TARGET_ABS=$(readlink -m "$TARGET" 2>/dev/null)
else
    # Last resort: assume already absolute and unnormalized; let the prefix test handle it
    TARGET_ABS="$TARGET"
fi

[ -z "$TARGET_ABS" ] && exit 0

# Check if target is inside the worktree boundary
# Append slash to avoid prefix-collision (e.g., /repo-main being matched by /repo)
case "$TARGET_ABS/" in
    "$WORKTREE_TOP_ABS"/*)
        # Inside worktree — allowed
        exit 0
        ;;
esac

# Target is outside worktree boundary
MODE="${CC_WORKTREE_BOUNDARY_MODE:-warn}"
QUIET="${CC_WORKTREE_BOUNDARY_QUIET:-0}"

if [ "$QUIET" != "1" ]; then
    echo "WORKTREE BOUNDARY: target outside active worktree." >&2
    echo "" >&2
    echo "  Worktree:  $WORKTREE_TOP_ABS" >&2
    echo "  Target:    $TARGET_ABS" >&2
    echo "  Tool:      $TOOL" >&2
    echo "" >&2
    echo "This Edit/Write call would land outside the worktree boundary the" >&2
    echo "system prompt declared. The parent main checkout (or another worktree)" >&2
    echo "may be modified without further confirmation. See anthropics/claude-code#59628." >&2
    echo "" >&2
    if [ "$MODE" = "block" ]; then
        echo "Mode: BLOCK (CC_WORKTREE_BOUNDARY_MODE=block). Edit refused." >&2
    else
        echo "Mode: WARN (advisory). To block instead, set CC_WORKTREE_BOUNDARY_MODE=block." >&2
    fi
fi

if [ "$MODE" = "block" ]; then
    exit 2
fi

exit 0
