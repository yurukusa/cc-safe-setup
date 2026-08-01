#!/bin/bash
# ================================================================
# worktree-delete-guard.sh — Block git worktree removal
# ================================================================
# PURPOSE:
#   Prevents one Claude session from deleting a worktree that
#   another session is actively using. Opus 4.6 has been observed
#   removing worktrees during cleanup without checking for
#   concurrent sessions. (#40850)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# WHAT IT BLOCKS:
#   - git worktree remove <path>
#   - git worktree prune
#   - rm -rf on worktree directories
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-worktree-delete-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [worktree-delete-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Block explicit worktree removal
if echo "$COMMAND" | grep -qE 'git\s+worktree\s+(remove|prune)'; then
    echo "BLOCKED: Cannot remove git worktrees — other sessions may depend on them." >&2
    echo "Command: $COMMAND" >&2
    echo "List worktrees first: git worktree list" >&2
    exit 2
fi

# Block rm on worktree paths (if we're in a git repo)
if git rev-parse --git-dir &>/dev/null; then
    COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [ -n "$COMMON_DIR" ]; then
        WORKTREES_DIR="${COMMON_DIR}/worktrees"
        if echo "$COMMAND" | grep -qE "(rm|rmdir)\s+.*worktrees"; then
            echo "BLOCKED: Cannot delete worktree storage directory." >&2
            exit 2
        fi
    fi
fi

exit 0
