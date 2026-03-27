#!/bin/bash
# multiline-command-approver.sh — Auto-approve multiline commands by first-line matching
#
# Solves: Auto-approve patterns fail on heredocs and multiline commands
#         (#11932 — 47 reactions, 29 comments)
#
# How it works:
#   1. Extracts the first line of the command
#   2. Matches against a whitelist of safe command prefixes
#   3. If the first line is a safe command, auto-approves the entire command
#
# This is needed because Claude Code's built-in pattern matching
# evaluates the entire multiline string, which breaks on heredocs:
#   echo 'commit message\n\nCo-Authored-By: ...' > file
#   ↑ This won't match Bash(echo:*) because of newlines
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/multiline-command-approver.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Extract first line only (handles heredocs, multiline strings)
FIRST_LINE=$(echo "$COMMAND" | head -1 | sed 's/^[[:space:]]*//')

# Safe command prefixes (first line only)
SAFE_PREFIXES=(
    "echo "
    "printf "
    "cat "
    "cat <<"
    "tee "
    "git commit"
    "git tag"
    "git log"
    "git status"
    "git diff"
    "git show"
    "git branch"
    "git stash"
    "npm test"
    "npm run"
    "npx "
    "python3 -c"
    "python3 -m"
    "node -e"
    "jq "
    "grep "
    "find "
    "ls "
    "wc "
    "head "
    "tail "
    "sort "
    "uniq "
    "tr "
    "cut "
    "sed "
    "awk "
    "curl -s"
)

for prefix in "${SAFE_PREFIXES[@]}"; do
    if [[ "$FIRST_LINE" == "$prefix"* ]]; then
        # Auto-approve: first line matches a safe prefix
        jq -n '{
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "multiline-command-approver: first line matches safe prefix"
            }
        }'
        exit 0
    fi
done

# No match — pass through (no opinion)
exit 0
