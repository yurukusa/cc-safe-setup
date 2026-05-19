#!/bin/bash
# worktree-hooks-path-fix.sh — Unset bogus per-worktree core.hooksPath that
# Claude Code's EnterWorktree harness writes, so Husky / lefthook / pre-commit
# hooks fire in worktrees the same way they do in the main checkout.
#
# Solves: #60620 — Claude Code's EnterWorktree harness writes an absolute
# `core.hooksPath` into the per-worktree `config.worktree` file. The absolute
# path points at the *main checkout's* hooks directory, not the worktree's,
# and because `extensions.worktreeConfig = true` is also enabled, the
# worktree-scoped value overrides any correct shared `core.hooksPath`
# (e.g. Husky's repo-relative `frontend/.husky/_`).
#
# Net effect: every Husky / lefthook / pre-commit hook the project author
# installed is dormant inside Claude-created worktrees. Git silently runs
# zero hooks (most common case) or runs the wrong directory's hooks against
# the worktree's index (less common but still a silent context drift).
#
# Operator-side fix: at SessionStart, detect that we're inside a
# Claude-created worktree (path matches `.claude/worktrees/`), read the
# worktree's `config.worktree` for `core.hooksPath`, and unset it if it is
# an absolute path that does not resolve relative to the worktree root.
# The shared config's repo-relative `core.hooksPath` (set by Husky's
# `prepare` script) then takes over and resolves correctly from any
# worktree.
#
# This is a harness-bug workaround, not a model-drift hook. The
# recognition-without-arrest family at #60226 is a different shape; this
# Issue's failure fires before any model interaction.
#
# Related Issues:
#   #60620 — Claude Code agent harness writes broken per-worktree
#            core.hooksPath (the direct origin of this hook)
#   #27474 — earlier failure mode in the same family (writes corrupted
#            shared .git/config; closed but related)
#   #60475 — sibling-session git checkout clobber (workspace-lease-guard
#            addresses a different worktree failure)
#
# CONFIG:
#   CC_WORKTREE_HOOKS_FIX_DISABLE=1   set to disable the hook entirely
#   CC_WORKTREE_HOOKS_FIX_VERBOSE=1   emit a NOTICE on every fix
#
# TRIGGER: SessionStart
# MATCHER: "*"

set -u

[ "${CC_WORKTREE_HOOKS_FIX_DISABLE:-0}" = "1" ] && exit 0

# Identify the working tree. Prefer CLAUDE_PROJECT_DIR, fall back to PWD.
WORKING_TREE="${CLAUDE_PROJECT_DIR:-${PWD:-}}"
[ -z "$WORKING_TREE" ] && exit 0

# Confirm we are inside a git worktree (not the main checkout, not non-git).
WORKTREE_ROOT=$(git -C "$WORKING_TREE" rev-parse --show-toplevel 2>/dev/null)
[ -z "$WORKTREE_ROOT" ] && exit 0

# Detect whether this is a worktree (vs the main checkout). git rev-parse
# --git-common-dir differs from --git-dir only inside a linked worktree.
GIT_COMMON_DIR=$(git -C "$WORKTREE_ROOT" rev-parse --git-common-dir 2>/dev/null)
GIT_DIR=$(git -C "$WORKTREE_ROOT" rev-parse --git-dir 2>/dev/null)
[ -z "$GIT_DIR" ] && exit 0

# Resolve both to absolute paths for comparison
GIT_COMMON_DIR_ABS=$(cd "$WORKTREE_ROOT" && readlink -f "$GIT_COMMON_DIR" 2>/dev/null || echo "$GIT_COMMON_DIR")
GIT_DIR_ABS=$(cd "$WORKTREE_ROOT" && readlink -f "$GIT_DIR" 2>/dev/null || echo "$GIT_DIR")

# Not a linked worktree — nothing to fix
[ "$GIT_COMMON_DIR_ABS" = "$GIT_DIR_ABS" ] && exit 0

# Only act on worktrees that look Claude-created. The path pattern
# `.claude/worktrees/` is the standard surface for `EnterWorktree`.
case "$WORKTREE_ROOT" in
    */.claude/worktrees/*) ;;
    *) exit 0 ;;
esac

# Read the worktree-scoped core.hooksPath
WORKTREE_HOOKS_PATH=$(git -C "$WORKTREE_ROOT" config --worktree --get core.hooksPath 2>/dev/null || true)
[ -z "$WORKTREE_HOOKS_PATH" ] && exit 0

# If the value is already a relative path resolving inside the worktree,
# leave it alone. Only intervene when it is an absolute path. Both POSIX-
# style (/) and Windows-style (C:\, D:\, etc.) absolute paths qualify.
case "$WORKTREE_HOOKS_PATH" in
    /*|[A-Za-z]:[\\/]*) ;;  # absolute — proceed
    *) exit 0 ;;            # relative — already correct, leave alone
esac

# If the absolute path happens to resolve inside the worktree root, leave
# it alone — the harness wrote something that works for this case.
case "$WORKTREE_HOOKS_PATH" in
    "$WORKTREE_ROOT"/*) exit 0 ;;
esac

# Otherwise: the worktree config has an absolute hooksPath pointing
# outside the worktree, which silently shadows the shared config's
# relative hooksPath. Unset it.
if git -C "$WORKTREE_ROOT" config --worktree --unset core.hooksPath 2>/dev/null; then
    if [ "${CC_WORKTREE_HOOKS_FIX_VERBOSE:-0}" = "1" ] || [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
        cat >&2 <<EOF
NOTICE: worktree-hooks-path-fix unset a bogus core.hooksPath in this worktree.
  Worktree:      ${WORKTREE_ROOT}
  Was pointing:  ${WORKTREE_HOOKS_PATH}
  Effect:        Husky / lefthook / pre-commit hooks installed via the
                 shared config will now fire correctly in this worktree
                 (Issue #60620 workaround).
EOF
    fi
fi

exit 0
