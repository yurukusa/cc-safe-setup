#!/bin/bash
# main-branch-warn.sh — Warn when working directly on main/master
#
# Prevents: Accidental commits and pushes to the default branch.
#           Encourages feature branch workflow.
#
# Checks the current git branch before every Bash command that
# modifies files (git add, git commit, npm publish, etc.)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/main-branch-warn.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check for commands that modify state
echo "$COMMAND" | grep -qE '^\s*(git\s+(add|commit|push|merge|rebase)|npm\s+publish)' || exit 0

# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$BRANCH" ] && exit 0

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "WARNING: You are on '$BRANCH'. Consider creating a feature branch:" >&2
  echo "  git checkout -b feature/your-task" >&2
  # Warning only — does not block. Change exit 0 to exit 2 to block.
fi

exit 0
