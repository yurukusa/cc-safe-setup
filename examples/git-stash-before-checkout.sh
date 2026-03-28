#!/bin/bash
# ================================================================
# git-stash-before-checkout.sh — Auto-stash before risky git checkouts
# ================================================================
# PURPOSE:
#   Prevents loss of uncommitted work when Claude runs git checkout
#   on a dirty working tree. Common scenario: Claude decides to
#   "check what the file looked like before" and runs git checkout,
#   wiping your uncommitted changes.
#
#   This hook checks for uncommitted changes before any git checkout
#   and blocks it with a suggestion to stash or commit first.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git *)",
#         "command": "~/.claude/hooks/git-stash-before-checkout.sh"
#       }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git checkout commands (not git checkout -b which creates branches)
if echo "$COMMAND" | grep -qE '^\s*git\s+checkout\s+' && ! echo "$COMMAND" | grep -qE 'git\s+checkout\s+-b\s'; then
    # Check if working tree is dirty
    if git status --porcelain 2>/dev/null | grep -qE '^.M|^.D|^\?\?'; then
        echo "BLOCKED: Uncommitted changes detected." >&2
        echo "git checkout on a dirty working tree may lose your changes." >&2
        echo "Run 'git stash' first, or commit your changes." >&2
        exit 2
    fi
fi

# Also check git restore -- which can discard changes
if echo "$COMMAND" | grep -qE '^\s*git\s+restore\s+--\s'; then
    echo "BLOCKED: git restore -- discards uncommitted changes." >&2
    echo "This cannot be undone. Commit or stash first." >&2
    exit 2
fi

exit 0
