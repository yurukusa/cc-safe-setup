#!/bin/bash
# ================================================================
# parallel-edit-guard.sh — Detect concurrent edits to same file
# ================================================================
# PURPOSE:
#   When Claude uses subagents (Agent tool), multiple agents can
#   try to edit the same file simultaneously, causing conflicts
#   and lost changes. This hook uses lock files to detect and
#   warn about concurrent edits.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"
# ================================================================

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Create a lock directory for tracking
LOCK_DIR="/tmp/cc-edit-locks"
mkdir -p "$LOCK_DIR"

# Normalize file path for lock name
LOCK_FILE="$LOCK_DIR/$(echo "$FILE" | md5sum | cut -c1-16).lock"

# Check if another process has a lock
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null)

    # Lock is stale if older than 30 seconds
    if [ "$LOCK_AGE" -lt 30 ] && [ "$LOCK_PID" != "$$" ]; then
        echo "WARNING: File $FILE may be edited by another agent." >&2
        echo "Lock age: ${LOCK_AGE}s, PID: $LOCK_PID" >&2
        echo "Wait for the other edit to complete." >&2
    fi
fi

# Set our lock
echo "$$" > "$LOCK_FILE"

# Clean up lock after 30s in background
(sleep 30 && rm -f "$LOCK_FILE") &>/dev/null &

exit 0
