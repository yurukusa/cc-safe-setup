#!/bin/bash
# git-signed-commit-guard.sh — Warn on unsigned git commits
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0
# Check if GPG signing is configured
SIGN=$(git config commit.gpgsign 2>/dev/null)
if [ "$SIGN" = "true" ] && echo "$COMMAND" | grep -q '\-\-no-gpg-sign'; then
    echo "WARNING: Commit with --no-gpg-sign bypasses GPG signing policy." >&2
fi
exit 0
