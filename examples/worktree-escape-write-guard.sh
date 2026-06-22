#!/bin/bash
# ================================================================
# worktree-escape-write-guard.sh — Block Edit/Write that escape the
#   active worktree and silently land on the main checkout
# ================================================================
# PURPOSE:
#   When a session runs in a git worktree under .claude/worktrees/<name>,
#   the model can resolve a repo-root-relative reference (e.g. an
#   auto-memory/notes line listing "packages/x/y.ts") against the
#   canonical repo root instead of the worktree root. The absolute path
#   "<repo>/packages/x/y.ts" is a valid, EXISTING file — just the wrong
#   copy. Edits then succeed silently on the MAIN checkout while cwd and
#   gitBranch keep reporting the worktree the whole time. The worktree
#   branch stays empty; nearly all work lands on the main branch, with
#   no warning. The author usually notices long after.
#
#   This is a data-loss-class accident: work you believe is isolated in a
#   worktree is written to (and committed on) the main checkout, and can
#   be lost outright if that branch is later rebased or force-pushed.
#
# HOW IT WORKS: PreToolUse hook on Edit|Write|MultiEdit. If cwd is inside
#   a worktree (.claude/worktrees/<name>), it derives the worktree root
#   and the repo root from cwd alone, then blocks any ABSOLUTE file_path
#   that is under the repo root but OUTSIDE the worktree root (i.e. the
#   main checkout's copy). Relative paths resolve against cwd (the
#   worktree) and are allowed. Absolute paths fully outside the repo are
#   not this guard's concern (other guards cover that).
#
# See: https://github.com/anthropics/claude-code/issues/70069
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write|MultiEdit"
#
# Configuration:
#   CC_WORKTREE_DIR_MARKER — path segment identifying worktrees.
#                            Default: ".claude/worktrees"
# ================================================================

set -euo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$CWD" ] && exit 0
[ -z "$FILE" ] && exit 0

MARKER="${CC_WORKTREE_DIR_MARKER:-.claude/worktrees}"

# Only act when the session is inside a worktree.
case "$CWD" in
    *"/$MARKER/"*) ;;
    *) exit 0 ;;
esac

# Derive repo root (prefix before the marker) and worktree root
# (prefix + marker + the first segment after it = the worktree name).
REPO_ROOT="${CWD%%/$MARKER/*}"
REST="${CWD#*/$MARKER/}"     # "<name>" or "<name>/sub/dir"
WT_NAME="${REST%%/*}"
WT_ROOT="$REPO_ROOT/$MARKER/$WT_NAME"

# Relative file_path resolves against cwd (the worktree) — safe.
case "$FILE" in
    /*) ;;      # absolute — keep checking
    *) exit 0 ;;
esac

# Absolute paths that stay within the worktree are fine.
case "$FILE" in
    "$WT_ROOT"|"$WT_ROOT"/*) exit 0 ;;
esac

# Absolute path under the repo root but outside the worktree = the bug.
case "$FILE" in
    "$REPO_ROOT"/*)
        echo "BLOCKED: Edit/Write escapes the active worktree onto the main checkout." >&2
        echo "" >&2
        echo "  Worktree (cwd): $WT_ROOT" >&2
        echo "  Target file:    $FILE" >&2
        echo "" >&2
        echo "This path is under the repository root but OUTSIDE the worktree." >&2
        echo "It points at the MAIN checkout's copy of the file, not the worktree's." >&2
        echo "Writing here silently commits your work to the main branch while the" >&2
        echo "worktree branch stays empty (Claude Code issue #70069)." >&2
        echo "" >&2
        echo "Fix: rewrite the path under the worktree root, e.g." >&2
        echo "  $WT_ROOT/<path-relative-to-repo>" >&2
        echo "" >&2
        echo "Override (only if you truly mean the main checkout): set" >&2
        echo "CC_WORKTREE_DIR_MARKER to a non-matching value for this command." >&2
        exit 2
        ;;
esac

# Absolute path entirely outside the repo — not this guard's concern.
exit 0
