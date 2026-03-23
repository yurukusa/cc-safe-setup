#!/bin/bash
# ================================================================
# loop-detector.sh — Detect and break command repetition loops
# ================================================================
# PURPOSE:
#   Claude Code sometimes gets stuck repeating the same command
#   or cycle of commands. This hook detects repetition and warns
#   before the loop wastes context and time.
#
# HOW IT WORKS:
#   1. Records last N commands in a state file
#   2. Checks if the current command matches recent commands
#   3. If same command appears 3+ times in last 5 calls → warn
#   4. If same command appears 5+ times → block
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# CONFIGURATION:
#   CC_LOOP_WARN=3    — warn after this many repeats (default: 3)
#   CC_LOOP_BLOCK=5   — block after this many repeats (default: 5)
#   CC_LOOP_WINDOW=10 — number of recent commands to track (default: 10)
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

STATE_FILE="/tmp/cc-loop-detector-history"
WARN_THRESHOLD="${CC_LOOP_WARN:-3}"
BLOCK_THRESHOLD="${CC_LOOP_BLOCK:-5}"
WINDOW="${CC_LOOP_WINDOW:-10}"

# Normalize command (strip whitespace variations)
NORMALIZED=$(echo "$COMMAND" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')

# Record command
echo "$NORMALIZED" >> "$STATE_FILE"

# Keep only last N entries
if [ -f "$STATE_FILE" ]; then
    tail -n "$WINDOW" "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# Count occurrences of current command in history
COUNT=$(grep -cF "$NORMALIZED" "$STATE_FILE" 2>/dev/null || echo 0)

if [ "$COUNT" -ge "$BLOCK_THRESHOLD" ]; then
    echo "BLOCKED: Command repeated $COUNT times in last $WINDOW calls." >&2
    echo "" >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "This looks like an infinite loop. Try a different approach." >&2
    echo "To reset: rm /tmp/cc-loop-detector-history" >&2
    exit 2
elif [ "$COUNT" -ge "$WARN_THRESHOLD" ]; then
    echo "WARNING: Command repeated $COUNT times. Possible loop." >&2
    echo "Command: $(echo "$COMMAND" | head -c 100)" >&2
fi

exit 0
