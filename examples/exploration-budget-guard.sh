#!/bin/bash
# exploration-budget-guard.sh — Stop excessive exploration from draining tokens
#
# Solves: #51054 — Claude wastes 20% of weekly allowance exploring files
#         on a simple task instead of acting. Read/Glob/Grep loops with
#         no Edit/Write progress.
#
# Tracks read-only tool calls (Read, Glob, Grep) per session. After 25
# consecutive reads without a write, warns. After 40, blocks.
# Resets when an Edit/Write/Bash(write) occurs.
#
# TRIGGER: PreToolUse  MATCHER: "Read|Glob|Grep|Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

STATE_DIR="/tmp/.cc-exploration-budget"
mkdir -p "$STATE_DIR"

# Session-scoped state file (keyed by parent PID)
STATE_FILE="$STATE_DIR/session-$$"
# Fall back to a shared file if $$ changes between hook calls
STATE_FILE="$STATE_DIR/exploration-count"

NOW=$(date +%s)

case "$TOOL" in
  Edit|Write)
    # Write operation = progress. Reset exploration counter.
    echo "0 $NOW" > "$STATE_FILE"
    exit 0
    ;;
  Read|Glob|Grep)
    # Read operation = exploration. Increment counter.
    ;;
  *)
    exit 0
    ;;
esac

# Read current count
COUNT=0
LAST_TIME=0
if [ -f "$STATE_FILE" ]; then
    read -r COUNT LAST_TIME < "$STATE_FILE" 2>/dev/null || true
    # Reset if more than 10 minutes since last call (new task)
    ELAPSED=$(( NOW - LAST_TIME ))
    if [ "$ELAPSED" -gt 600 ]; then
        COUNT=0
    fi
fi

COUNT=$(( COUNT + 1 ))
echo "$COUNT $NOW" > "$STATE_FILE"

WARN_THRESHOLD=25
BLOCK_THRESHOLD=40

if [ "$COUNT" -ge "$BLOCK_THRESHOLD" ]; then
    echo "BLOCKED: $COUNT consecutive read operations without writing anything." >&2
    echo "  You're stuck in an exploration loop — this wastes tokens." >&2
    echo "  Take action NOW:" >&2
    echo "  1. Write your solution based on what you've already read" >&2
    echo "  2. If unsure, make a small change and test it" >&2
    echo "  3. Ask the user for clarification instead of reading more files" >&2
    echo "" >&2
    echo "  Exploration budget: $COUNT/$BLOCK_THRESHOLD (EXCEEDED)" >&2
    exit 2
fi

if [ "$COUNT" -ge "$WARN_THRESHOLD" ]; then
    echo "WARNING: $COUNT consecutive reads without any write." >&2
    echo "  You may be over-exploring. Consider acting on what you know." >&2
    echo "  Budget: $COUNT/$BLOCK_THRESHOLD reads before block." >&2
fi

exit 0
