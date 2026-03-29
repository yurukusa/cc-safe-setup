#!/bin/bash
# ================================================================
# git-show-flag-sanitizer.sh — Strip invalid --no-stat from git show
# ================================================================
# PURPOSE:
#   Claude Code frequently runs `git show <ref> --no-stat`, but --no-stat
#   is not a valid git-show flag. The command fails with exit code 128,
#   wasting context on error output and retries.
#   This hook silently rewrites the command to remove --no-stat.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# See: https://github.com/anthropics/claude-code/issues/13071
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only act on git show commands containing --no-stat
case "$COMMAND" in
  *git\ show*--no-stat*|*git\ show*--no-stat*) ;;
  *) exit 0 ;;
esac

# Remove --no-stat flag (handles multiple spaces)
NEW_COMMAND=$(echo "$COMMAND" | sed 's/ --no-stat//')

# Collapse any double spaces left behind
NEW_COMMAND=$(echo "$NEW_COMMAND" | sed 's/  */ /g')

jq -n --arg cmd "$NEW_COMMAND" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: { command: $cmd }
  }
}'

exit 0
