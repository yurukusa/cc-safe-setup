#!/bin/bash
# no-git-amend.sh — Block git commit --amend to prevent overwriting previous commits
#
# Solves: Claude Code amending previous commits instead of creating new ones.
#         When a pre-commit hook fails, the commit doesn't happen. If Claude
#         then runs --amend to "fix" it, it modifies the PREVIOUS commit
#         instead of creating a new one — potentially destroying prior work.
#
# This is explicitly recommended in Claude Code's own system prompt:
#   "Always create NEW commits rather than amending"
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Block git commit --amend
if echo "$COMMAND" | grep -qE 'git\s+commit\s+.*--amend|git\s+commit\s+--amend'; then
    echo "BLOCKED: git commit --amend is not allowed" >&2
    echo "  Create a new commit instead: git commit -m 'fix: ...'" >&2
    echo "  Amending can overwrite the previous commit's changes." >&2
    exit 2
fi

exit 0
