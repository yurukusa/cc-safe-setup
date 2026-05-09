#!/bin/bash
# ================================================================
# subagent-destructive-git-guard.sh — Warn when subagent prompt
#                                     lacks destructive-git boundary
# ================================================================
# PURPOSE:
#   When the main agent spawns a subagent via the Agent tool, checks
#   whether the delegation prompt explicitly forbids destructive git
#   commands (git checkout HEAD, git checkout -- <files>, git restore,
#   git reset --hard, worktree cleanup) and tells the subagent to
#   prefer git stash for any "undo" recovery. Warns via stderr when
#   these destructive-git boundary instructions are missing.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"
#
# WHY THIS MATTERS:
#   Issue #57463 reported a general-purpose subagent that, after a bad
#   bulk sed pass, recovered via "git checkout -- <files>" and silently
#   wiped unrelated uncommitted user edits on the same files. The
#   subagent did not run git status / git diff first, did not stash,
#   did not warn the user, and reported the action as one line buried
#   in a summary. The parent had no opportunity to intervene.
#
#   The same shape appears in #46444 (worktree auto-cleanup deleted 10
#   days of work) and #53765 (Sonnet 4.6 ran git checkout HEAD twice
#   despite an explicit memory rule). Three independent reports across
#   April 25 to May 8, 2026, share the same failure structure: an
#   autonomous "undo" uses a destructive git command without checking
#   the working tree first.
#
#   Existing hooks (uncommitted-discard-guard.sh, git-checkout-
#   uncommitted-guard.sh, worktree-remove-uncommitted-guard.sh) block
#   the Bash command at the parent's PreToolUse layer. This hook is
#   the prevention layer one level higher: it nudges the parent to
#   include explicit destructive-git boundary instructions in the
#   delegation prompt itself, so the subagent's planning stage has the
#   constraint, not just the execution stage.
#
# WHAT IT CHECKS:
#   1. Prompt forbids destructive git commands by name (e.g.
#      "do not use git checkout", "no git reset", "禁止: git restore",
#      "destructive git commands forbidden")
#   2. Prompt names the safe alternative for "undo" (e.g.
#      "use git stash", "stash before checkout", "reverse sed instead
#      of checkout", "ask the parent before any destructive operation")
#   3. Prompt asks the subagent to run git status / git diff first if
#      it considers any working-tree-modifying command (e.g.
#      "check git status first", "run git diff before any change",
#      "verify working tree state before recovery")
#
# OUTPUT:
#   Warning to stderr listing which destructive-git boundary
#   instructions are missing. Always exits 0 by default — advisory
#   only, never blocks.
#
# CONFIGURATION:
#   CC_SUBAGENT_DESTRUCTIVE_GIT_REQUIRE_ALL — set to "1" to block when
#       any check fails (default: warn only)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/57463
#   https://github.com/anthropics/claude-code/issues/46444
#   https://github.com/anthropics/claude-code/issues/53765
# ================================================================

set -u

INPUT=$(cat)

PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

if [ -z "$PROMPT" ]; then
    exit 0
fi

WARNINGS=""

# Check 1: Destructive git commands forbidden
if ! printf '%s' "$PROMPT" | grep -qiE 'do not (use|run) (git )?(checkout|reset|restore)|no (git )?(checkout|reset|restore)|never (use|run) (git )?(checkout|reset|restore)|forbidden:? (git )?(checkout|reset|restore)|destructive git|破壊的な git|禁止:? (git )?(checkout|reset|restore)|git (checkout|reset|restore).{0,20}(禁止|forbidden|prohibited)'; then
    WARNINGS="${WARNINGS}  - Destructive git commands not forbidden by name. Subagent may use git checkout / git reset / git restore for its own recovery, silently wiping uncommitted user work (Issue #57463).\n"
fi

# Check 2: Safe alternative named
if ! printf '%s' "$PROMPT" | grep -qiE 'use git stash|stash before|stash first|reverse (sed|edit|change)|ask (the )?parent before|return to (the )?parent before any destructive|stash の利用|親に確認'; then
    WARNINGS="${WARNINGS}  - No safe alternative named for undo. Subagent has no fallback when its own action needs reverting; falls back to destructive checkout.\n"
fi

# Check 3: Working tree state check first
if ! printf '%s' "$PROMPT" | grep -qiE 'check git status|run git status (first|before)|git diff (first|before)|verify working tree|working tree (state|status) (first|before)|git status を最初に|作業の場の状態を(確認|検査)'; then
    WARNINGS="${WARNINGS}  - No working-tree state check. Subagent may run destructive commands without seeing what's at risk (Issue #46444 / #53765 / #57463 all share this gap).\n"
fi

if [ -n "$WARNINGS" ]; then
    REQUIRE_ALL="${CC_SUBAGENT_DESTRUCTIVE_GIT_REQUIRE_ALL:-0}"
    printf '⚠️  Subagent destructive-git boundary not enforced in delegation prompt:\n' >&2
    printf '%b' "$WARNINGS" >&2
    printf '\n  References:\n' >&2
    printf '    https://github.com/anthropics/claude-code/issues/57463 (subagent git checkout wiped uncommitted edits)\n' >&2
    printf '    https://github.com/anthropics/claude-code/issues/46444 (worktree auto-cleanup deleted 10 days of work)\n' >&2
    printf '    https://github.com/anthropics/claude-code/issues/53765 (Sonnet 4.6 ran git checkout HEAD twice despite memory rule)\n' >&2
    printf '\n  Recommended fix: in the delegation prompt, name destructive git commands as forbidden, name git stash as the safe alternative, and instruct the subagent to run git status before any recovery.\n' >&2
    if [ "$REQUIRE_ALL" = "1" ]; then
        exit 2
    fi
fi

exit 0
