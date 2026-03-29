#!/bin/bash
# branch-name-check.sh — Warn when creating branches with non-standard names
#
# Checks for conventional branch naming (feature/, fix/, hotfix/, etc.)
# and blocks branches with spaces, uppercase, or special characters.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/branch-name-check.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check branch creation commands
if ! echo "$COMMAND" | grep -qE 'git\s+(checkout\s+-b|branch|switch\s+-c)\s'; then
    exit 0
fi

# Extract branch name
BRANCH=$(echo "$COMMAND" | grep -oP '(?:checkout\s+-b|branch|switch\s+-c)\s+\K\S+')
[[ -z "$BRANCH" ]] && exit 0

# Check for spaces or special characters
if echo "$BRANCH" | grep -qP '[^a-zA-Z0-9/_.-]'; then
    echo "" >&2
    echo "WARNING: Branch name contains special characters: $BRANCH" >&2
    echo "Use only: a-z, 0-9, /, -, ., _" >&2
fi

# Check for conventional prefix
if ! echo "$BRANCH" | grep -qE '^(feature|fix|hotfix|bugfix|release|chore|docs|refactor|test|ci)/'; then
    echo "" >&2
    echo "NOTE: Branch doesn't follow conventional naming." >&2
    echo "Consider: feature/, fix/, hotfix/, chore/, docs/" >&2
fi

exit 0
