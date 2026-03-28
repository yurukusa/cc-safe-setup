#!/bin/bash
# git-checkout-uncommitted-guard.sh — Block branch switching with uncommitted changes
#
# Solves: Claude Code switching branches while uncommitted changes exist,
#         causing silent data loss when the target branch overwrites modified files.
#         Real incident: #39394 — hours of work lost when Claude decided to
#         organize commits on a different branch.
#
# Why this matters: git checkout <branch> silently overwrites modified files
# if the target branch has different versions. Unlike "git checkout -- .",
# the user doesn't intend to discard changes — they just wanted to switch
# branches. The data loss is a side effect, not the goal.
#
# Detects:
#   git checkout <branch>     (when uncommitted changes exist)
#   git switch <branch>       (modern equivalent)
#
# Does NOT block:
#   git checkout -b <branch>  (creating new branch — preserves changes)
#   git switch -c <branch>    (creating new branch — preserves changes)
#   git checkout -- <files>   (handled by uncommitted-discard-guard)
#   Any checkout when working tree is clean
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only check git checkout/switch commands (not -b/-c which create branches)
IS_CHECKOUT=false
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+[^-]' && ! echo "$COMMAND" | grep -qE 'git\s+checkout\s+(-b|-B)\s'; then
    # Exclude "git checkout -- <files>" (handled elsewhere)
    echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s' && exit 0
    IS_CHECKOUT=true
fi
if echo "$COMMAND" | grep -qE 'git\s+switch\s+[^-]' && ! echo "$COMMAND" | grep -qE 'git\s+switch\s+(-c|-C)\s'; then
    IS_CHECKOUT=true
fi

[ "$IS_CHECKOUT" = "false" ] && exit 0

# Check for uncommitted changes
DIRTY=$(git status --porcelain 2>/dev/null | head -1)
if [ -n "$DIRTY" ]; then
    CHANGED=$(git status --porcelain 2>/dev/null | wc -l)
    echo "BLOCKED: Cannot switch branches with $CHANGED uncommitted change(s)." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "Uncommitted changes would be overwritten by the target branch." >&2
    echo "Options:" >&2
    echo "  git stash           # save changes, switch, then git stash pop" >&2
    echo "  git commit -m 'WIP' # commit changes before switching" >&2
    echo "  git checkout -b <new-branch>  # create branch (keeps changes)" >&2
    exit 2
fi

exit 0
