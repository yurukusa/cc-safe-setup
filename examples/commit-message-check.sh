#!/bin/bash
# commit-message-check.sh — Warn when commit messages don't follow conventions
#
# Checks for conventional commits format (feat:, fix:, docs:, etc.)
# and minimum message length.
#
# This is a PostToolUse hook — it checks AFTER git commit runs
# and warns if the message doesn't follow conventions.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git commit *)",
#         "command": "~/.claude/hooks/commit-message-check.sh"
#       }]
#     }]
#   }
# }
#
# The "if" field (v2.1.85+) skips this hook for non-commit commands.
# Without "if", the hook still works — it checks internally and exits early.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check after git commit
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
    exit 0
fi

# Must be in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Get the last commit message
MSG=$(git log -1 --pretty=%s 2>/dev/null)
[[ -z "$MSG" ]] && exit 0

# Check conventional commit format
if ! echo "$MSG" | grep -qE '^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\(.+\))?(!)?:'; then
    echo "" >&2
    echo "NOTE: Commit message doesn't follow conventional commits format." >&2
    echo "Expected: feat|fix|docs|chore|...: description" >&2
    echo "Got: $MSG" >&2
fi

# Check minimum length
if (( ${#MSG} < 10 )); then
    echo "" >&2
    echo "NOTE: Commit message is very short (${#MSG} chars)." >&2
    echo "Consider adding more context." >&2
fi

exit 0
