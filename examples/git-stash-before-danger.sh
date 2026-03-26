#!/bin/bash
# git-stash-before-danger.sh — Auto-stash before risky git operations
#
# Solves: Losing uncommitted work when Claude runs git checkout, git reset, or git pull
#         Related: data loss incidents reported in #36339, #37331
#
# How it works: PreToolUse hook that auto-runs `git stash push -m "cc-auto-stash"`
#               before destructive git operations. The stash can be recovered with
#               `git stash pop`.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/git-stash-before-danger.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only act on risky git operations
RISKY=false
if echo "$COMMAND" | grep -qE 'git\s+(checkout|reset|pull|merge|rebase|cherry-pick)\s'; then
    RISKY=true
fi

if [ "$RISKY" = false ]; then
    exit 0
fi

# Check if we're in a git repo with uncommitted changes
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    exit 0
fi

# Check for uncommitted changes
if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    # No changes — nothing to stash
    exit 0
fi

# Auto-stash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
git stash push -m "cc-auto-stash-$TIMESTAMP (before: $COMMAND)" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "INFO: Auto-stashed uncommitted changes before risky operation" >&2
    echo "Recovery: git stash pop" >&2
fi

# Don't block — just stash and let the command proceed
exit 0
