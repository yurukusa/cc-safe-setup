#!/bin/bash
# concurrent-edit-lock.sh — Prevent file corruption from concurrent Claude sessions
#
# Solves: File corruption when running multiple Claude Code terminals (#35682).
#         Two sessions editing the same file simultaneously can produce
#         interleaved writes, truncated content, or merge conflicts.
#
# How it works: PreToolUse hook on Edit/Write that creates a lock file
#   before editing. If another session holds the lock, blocks the edit.
#   Lock auto-expires after 60 seconds (configurable) to prevent deadlocks.
#
# CONFIG:
#   CC_EDIT_LOCK_TIMEOUT=60  # seconds before lock expires
#
# TRIGGER: PreToolUse
# MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

LOCK_DIR="${HOME}/.claude/locks"
mkdir -p "$LOCK_DIR"

LOCK_TIMEOUT=${CC_EDIT_LOCK_TIMEOUT:-60}

# Create a hash of the file path for the lock file name
LOCK_HASH=$(echo "$FILE" | md5sum | cut -c1-16)
LOCK_FILE="${LOCK_DIR}/${LOCK_HASH}.lock"
SESSION_ID="$$"

# Check for existing lock
if [ -f "$LOCK_FILE" ]; then
    LOCK_INFO=$(cat "$LOCK_FILE")
    LOCK_PID=$(echo "$LOCK_INFO" | cut -d'|' -f1)
    LOCK_TIME=$(echo "$LOCK_INFO" | cut -d'|' -f2)
    NOW=$(date +%s)

    # Check if lock is expired
    if [ $((NOW - LOCK_TIME)) -gt "$LOCK_TIMEOUT" ]; then
        # Lock expired — remove and proceed
        rm -f "$LOCK_FILE"
    elif [ "$LOCK_PID" != "$SESSION_ID" ]; then
        # Another session holds the lock
        # Check if the locking process is still alive
        if kill -0 "$LOCK_PID" 2>/dev/null; then
            echo "BLOCKED: File is being edited by another Claude session (PID ${LOCK_PID})" >&2
            echo "  File: $(basename "$FILE")" >&2
            echo "  Wait for the other session to finish, or remove lock: rm ${LOCK_FILE}" >&2
            exit 2
        else
            # Process is dead — stale lock
            rm -f "$LOCK_FILE"
        fi
    fi
fi

# Acquire lock
echo "${SESSION_ID}|$(date +%s)" > "$LOCK_FILE"

# Schedule lock cleanup (best effort — PostToolUse should handle this)
# The lock will expire naturally after LOCK_TIMEOUT seconds

exit 0
