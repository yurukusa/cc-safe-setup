#!/bin/bash
# token-spike-alert.sh — Alert on abnormal token consumption per turn
#
# Solves: Users report 10-20% of their 5-hour quota consumed by
#         a single lightweight question (#40524, #38029, #40881).
#         Cache invalidation causes full context re-processing,
#         spiking token usage without user awareness.
#
# How it works: Tracks tool call count per session via a counter
#   file. If more than MAX_TOOLS_PER_TURN tool calls happen in
#   rapid succession (within 30 seconds), warns about possible
#   runaway behavior that could spike token usage.
#
# TRIGGER: PostToolUse
# MATCHER: ""

set -euo pipefail

COUNTER_FILE="/tmp/claude-token-spike-$$"
MAX_TOOLS_PER_BURST="${MAX_TOOLS_PER_BURST:-15}"

# Get current timestamp
NOW=$(date +%s)

# Read last timestamp and count
if [ -f "$COUNTER_FILE" ]; then
  LAST_TS=$(head -1 "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=$(tail -1 "$COUNTER_FILE" 2>/dev/null || echo "0")
else
  LAST_TS=0
  COUNT=0
fi

# If within 30-second burst window
DELTA=$((NOW - LAST_TS))
if [ "$DELTA" -lt 30 ]; then
  COUNT=$((COUNT + 1))
else
  COUNT=1
fi

# Save state
echo "$NOW" > "$COUNTER_FILE"
echo "$COUNT" >> "$COUNTER_FILE"

# Alert if burst detected
if [ "$COUNT" -ge "$MAX_TOOLS_PER_BURST" ]; then
  echo "WARNING: $COUNT tool calls in ${DELTA}s burst. Possible runaway behavior — check token consumption." >&2
fi

exit 0
