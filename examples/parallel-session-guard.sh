#!/bin/bash
# ================================================================
# parallel-session-guard.sh — Warn when multiple Claude sessions
# edit the same project simultaneously
#
# Solves: Two Claude sessions editing the same files can cause
# merge conflicts, overwritten work, and inconsistent state.
# Common in worktree setups or when accidentally starting
# a second session in the same directory.
#
# Uses PID-based lock files in /tmp to detect concurrent sessions.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/parallel-session-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only guard write operations
case "$TOOL" in
    Edit|Write|NotebookEdit) ;;
    *) exit 0 ;;
esac

# Get project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
# Create a hash of the project path for the lock file
PROJECT_HASH=$(echo "$PROJECT_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1)
LOCK_DIR="/tmp/cc-session-locks"
LOCK_FILE="$LOCK_DIR/$PROJECT_HASH"

mkdir -p "$LOCK_DIR" 2>/dev/null

# Register this session
MY_PID=$$
if [[ -f "$LOCK_FILE" ]]; then
    OTHER_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    # Check if the other session is still running
    if [[ -n "$OTHER_PID" ]] && [[ "$OTHER_PID" != "$MY_PID" ]] && kill -0 "$OTHER_PID" 2>/dev/null; then
        echo "WARNING: Another Claude session (PID $OTHER_PID) is also editing this project." >&2
        echo "Project: $PROJECT_ROOT" >&2
        echo "Concurrent edits may cause conflicts. Consider using separate worktrees." >&2
    fi
fi

# Update lock with our PID
echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null

exit 0
