#!/bin/bash
# ================================================================
# error-memory-guard.sh — Detect repeated failed commands
# ================================================================
# PURPOSE:
#   Claude often retries the exact same command that just failed,
#   sometimes 5-10 times before trying a different approach.
#   This hook tracks command+error pairs and blocks retries of
#   commands that have already failed with the same error.
#
# TRIGGER: PostToolUse  MATCHER: "Bash"
#
# Unlike loop-detector (which catches any repetition), this
# specifically targets the "same command, same error" pattern.
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result_exit_code // 0' 2>/dev/null)
ERROR=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null | tail -5)

# Only track failures
[ "$EXIT_CODE" = "0" ] && exit 0

STATE="/tmp/cc-error-memory-$(echo "$PWD" | md5sum | cut -c1-8)"
HASH=$(echo "$COMMAND" | md5sum | cut -c1-16)

# Check if this exact command already failed
if grep -q "^$HASH:" "$STATE" 2>/dev/null; then
    PREV_COUNT=$(grep "^$HASH:" "$STATE" | cut -d: -f2)
    NEW_COUNT=$((PREV_COUNT + 1))
    sed -i "s/^$HASH:.*/$HASH:$NEW_COUNT/" "$STATE"

    if [ "$NEW_COUNT" -ge 3 ]; then
        echo "BLOCKED: This command has failed $NEW_COUNT times with the same error." >&2
        echo "Try a different approach instead of retrying." >&2
        echo "Command: $(echo "$COMMAND" | head -c 80)" >&2
        echo "Reset: rm $STATE" >&2
        exit 2
    elif [ "$NEW_COUNT" -ge 2 ]; then
        echo "WARNING: Command failed $NEW_COUNT times. Consider a different approach." >&2
    fi
else
    echo "$HASH:1" >> "$STATE"
fi

exit 0
