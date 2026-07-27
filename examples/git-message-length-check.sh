#!/bin/bash
# ================================================================
# git-message-length-check.sh — Warn on too-short commit messages
# ================================================================
# PURPOSE:
#   Claude Code sometimes writes very short commit messages like
#   "fix" or "update". This PostToolUse hook checks the commit
#   message length and warns if it's too short to be meaningful.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
#
# CONFIGURATION:
#   CC_COMMIT_MIN_LENGTH=10  (minimum message length, default: 10)
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git commit commands
echo "$COMMAND" | grep -qE 'git\s+commit' || exit 0

MIN_LENGTH="${CC_COMMIT_MIN_LENGTH:-10}"

# Extract message from -m flag
MSG=$(echo "$COMMAND" | grep -oE '\-m\s+["'"'"'][^"'"'"']*["'"'"']' | sed "s/-m\s*[\"']\(.*\)[\"']/\1/")
[ -z "$MSG" ] && exit 0

LENGTH=${#MSG}

if [ "$LENGTH" -lt "$MIN_LENGTH" ]; then
    echo "⚠ Commit message too short ($LENGTH chars, minimum: $MIN_LENGTH)" >&2
    echo "  Message: \"$MSG\"" >&2
    echo "  Write descriptive messages explaining WHY, not WHAT." >&2
fi

exit 0
