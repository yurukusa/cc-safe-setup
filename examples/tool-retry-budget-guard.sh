#!/bin/bash
# tool-retry-budget-guard.sh — Stop Claude from wasting tokens on repeated failures
#
# Solves: #50986 — Claude fails simple UI change after 10+ attempts, wastes entire
#         token budget. Also prevents retry spirals on any file.
#
# Tracks consecutive tool calls (Edit, Write, Bash) targeting the same file.
# After 5 attempts, blocks further edits and forces a different approach.
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Use file hash as state key
HASH=$(echo "$FILE" | md5sum | cut -c1-8)
STATE_DIR="/tmp/.cc-retry-budget"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$HASH"

# Track attempt count and timestamp
NOW=$(date +%s)
COUNT=1

if [ -f "$STATE_FILE" ]; then
    PREV_TIME=$(head -1 "$STATE_FILE" 2>/dev/null || echo "0")
    PREV_COUNT=$(tail -1 "$STATE_FILE" 2>/dev/null || echo "0")

    # Reset if more than 5 minutes since last attempt (new task)
    ELAPSED=$(( NOW - PREV_TIME ))
    if [ "$ELAPSED" -lt 300 ]; then
        COUNT=$(( PREV_COUNT + 1 ))
    fi
fi

printf '%s\n%s\n' "$NOW" "$COUNT" > "$STATE_FILE"

if [ "$COUNT" -ge 7 ]; then
    echo "BLOCKED: You've attempted to modify $(basename "$FILE") $COUNT times in the last 5 minutes." >&2
    echo "  This pattern wastes tokens. Stop and try a completely different approach:" >&2
    echo "  1. Read the file first to understand current state" >&2
    echo "  2. Use a different strategy (smaller change, different tool)" >&2
    echo "  3. If stuck, explain the problem and ask for help" >&2
    rm -f "$STATE_FILE"
    exit 2
elif [ "$COUNT" -ge 5 ]; then
    echo "WARNING: $COUNT consecutive edits to $(basename "$FILE") — approaching retry limit (7)." >&2
    echo "  Consider reading the file to verify your assumptions before the next attempt." >&2
fi

exit 0
