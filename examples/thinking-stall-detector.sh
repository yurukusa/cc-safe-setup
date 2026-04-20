#!/bin/bash
# thinking-stall-detector.sh — Detect when Claude's thinking phase stalls
#
# Solves: #51092 — Sonnet 4.6 thinking ran for 25 minutes, consuming
#         16M+ tokens. User lost entire token allowance to a single
#         reasoning phase that never produced output.
#
# HOW IT WORKS:
#   Tracks time between consecutive tool calls. If the gap exceeds
#   a threshold (default 5 minutes), it means Claude was "thinking"
#   without taking any action — likely a reasoning stall.
#
#   On detection, logs a warning with the stall duration and suggests
#   the user interrupt with Ctrl+C.
#
# WHY THIS MATTERS:
#   During thinking, tokens are consumed but no hooks fire. This hook
#   fires on the NEXT tool call after the stall, so it can't prevent
#   the stall itself — but it alerts the user that one occurred, so
#   they can watch for it happening again and interrupt early.
#
# TRIGGER: PreToolUse  MATCHER: ""
# Also works as: Notification (fires on status changes)
#
# CONFIGURATION:
#   CC_STALL_WARN_SECS=300    warn after 5-minute gap (default)
#   CC_STALL_LOG=/tmp/cc-thinking-stalls.log

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

STATE_FILE="/tmp/cc-thinking-stall-last-call"
LOG_FILE="${CC_STALL_LOG:-/tmp/cc-thinking-stalls.log}"
WARN_SECS="${CC_STALL_WARN_SECS:-300}"

NOW=$(date +%s)

# Read last tool call timestamp
LAST=$(cat "$STATE_FILE" 2>/dev/null || echo "$NOW")

# Update timestamp
echo "$NOW" > "$STATE_FILE"

# Calculate gap
GAP=$((NOW - LAST))

if [ "$GAP" -ge "$WARN_SECS" ]; then
    MINUTES=$((GAP / 60))
    REMAINDER=$((GAP % 60))

    # Log the stall
    echo "$(date -Iseconds) STALL ${MINUTES}m${REMAINDER}s before tool=$TOOL" >> "$LOG_FILE"

    # Warn the user
    echo "⚠️ Thinking stall detected: ${MINUTES}m${REMAINDER}s with no tool activity." >&2
    echo "This may indicate a reasoning loop consuming tokens silently." >&2
    echo "If this happens again, press Ctrl+C to interrupt." >&2
    echo "See #51092: 25-minute thinking stall consumed 16M tokens." >&2
fi

exit 0
