#!/bin/bash
# session-start-safety-check.sh — Warn about uncommitted changes on session start
#
# Solves: Claude Code running destructive git commands on session startup
#         that destroy uncommitted work (#34327, #39394)
#
# How it works:
#   On SessionStart, checks for:
#   1. Uncommitted changes (modified/new files)
#   2. Unpushed commits
#   3. Stashed changes that may need attention
#
#   Prints warnings but does NOT block (exit 0 always).
#   The goal is awareness, not prevention.
#
# TRIGGER: SessionStart
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-start-safety-check.sh" }]
#     }]
#   }
# }

# Only run in git repos
git rev-parse --git-dir > /dev/null 2>&1 || exit 0

WARNINGS=0

# Check for uncommitted changes
CHANGES=$(git status --porcelain 2>/dev/null | wc -l)
if [ "$CHANGES" -gt 0 ]; then
    echo "⚠ WARNING: $CHANGES uncommitted changes detected." >&2
    echo "  Consider: git stash  (before destructive operations)" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for unpushed commits
UNPUSHED=$(git log --oneline @{upstream}..HEAD 2>/dev/null | wc -l)
if [ "$UNPUSHED" -gt 0 ]; then
    echo "⚠ WARNING: $UNPUSHED unpushed commits." >&2
    echo "  Consider: git push  (to protect against local data loss)" >&2
    WARNINGS=$((WARNINGS + 1))
fi

# Check for stashes — and specifically surface crash/teleport "auto-stash"
# entries. When a session crashes or teleports between branches, Claude Code's
# teardown silently runs `git add` + `git stash push`, so a clean working tree
# does NOT mean the work was never done — it can be hidden in a stash that other
# agents/sessions never see. In a shared worktree this is how uncommitted work
# from research docs and code silently disappears (#66060).
STASHES=$(git stash list 2>/dev/null | wc -l)
if [ "$STASHES" -gt 0 ]; then
    # The teardown template is "auto-stash: agent <role> (<id>) crashed at <ts>",
    # so matching "auto-stash" is a high-confidence signal with no false positives
    # against the default "WIP on <branch>" messages of manual stashes.
    AUTO_STASHES=$(git stash list 2>/dev/null | grep -c 'auto-stash' || true)
    if [ "$AUTO_STASHES" -gt 0 ]; then
        echo "⚠ WARNING: $AUTO_STASHES of $STASHES stashes are crash/teleport auto-stashes." >&2
        echo "  Uncommitted work is hidden here; a clean working tree is NOT proof it was lost (#66060)." >&2
        echo "  Inspect:  git stash list | grep auto-stash" >&2
        echo "            git stash show -p 'stash@{N}'" >&2
        echo "  Recover:  checkout the branch in the stash's 'On <branch>:' label, then" >&2
        echo "            git stash apply 'stash@{N}'   (apply, not pop — keeps a safety copy)" >&2
        echo "  Root cause for multi-agent setups: agents sharing one worktree." >&2
        echo "            Give each agent its own 'git worktree' so a teardown can't reach the others." >&2
        # Hidden work that looks like a clean tree is a real hazard, so don't let
        # the all-clear line below claim everything is fine.
        WARNINGS=$((WARNINGS + 1))
    else
        echo "ℹ NOTE: $STASHES stashed changes exist." >&2
        echo "  Review: git stash list" >&2
    fi
fi

if [ "$WARNINGS" -eq 0 ]; then
    echo "✓ Working tree clean, all commits pushed." >&2
fi

exit 0
