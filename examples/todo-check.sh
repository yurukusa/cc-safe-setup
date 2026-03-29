#!/bin/bash
# todo-check.sh — Warn when committing files with TODO/FIXME/HACK comments
#
# PostToolUse hook that checks after git commit for remaining
# TODO/FIXME/HACK markers in the committed files.
#
# Usage: Add to settings.json as a PostToolUse hook
#
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/todo-check.sh" }]
#     }]
#   }
# }
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

# Check committed files for TODO/FIXME/HACK
COMMITTED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null)
[[ -z "$COMMITTED_FILES" ]] && exit 0

TODO_COUNT=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        MATCHES=$(grep -cnE '\bTODO\b|\bFIXME\b|\bHACK\b|\bXXX\b' "$file" 2>/dev/null || echo 0)
        TODO_COUNT=$((TODO_COUNT + MATCHES))
    fi
done <<< "$COMMITTED_FILES"

if (( TODO_COUNT > 0 )); then
    echo "" >&2
    echo "NOTE: $TODO_COUNT TODO/FIXME/HACK markers in committed files." >&2
    echo "Run: git diff-tree --no-commit-id --name-only -r HEAD | xargs grep -n 'TODO\|FIXME\|HACK'" >&2
fi

exit 0
