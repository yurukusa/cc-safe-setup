#!/bin/bash
# ================================================================
# compact-circuit-breaker.sh — Prevent auto-compact death spirals
# ================================================================
# PURPOSE:
#   Auto-compact can enter an infinite loop when FileHistory
#   recovery is degraded — each compaction fails to restore
#   continuity, triggering the next one immediately. Users have
#   lost entire overnight token budgets to 15+ consecutive
#   compactions with zero forward progress (#51088). One incident
#   recorded 211 compactions in a single session (#24179).
#
#   This hook acts as a circuit breaker: it allows normal
#   compaction but blocks rapid-fire compaction that indicates
#   a death spiral. After MAX_PER_HOUR compactions, further
#   attempts are blocked until the window resets.
#
# TRIGGER: PreCompact
# MATCHER: (none — PreCompact has no matcher)
#
# DECISION: exit 0 = allow, exit 2 = block
#
# CONFIG:
#   MAX_PER_HOUR — Maximum compactions allowed per hour (default: 3)
#   MIN_INTERVAL — Minimum seconds between compactions (default: 120)
#
# See: https://github.com/anthropics/claude-code/issues/51088
#      https://github.com/anthropics/claude-code/issues/24179
# ================================================================

MAX_PER_HOUR="${CC_COMPACT_MAX_PER_HOUR:-3}"
MIN_INTERVAL="${CC_COMPACT_MIN_INTERVAL:-120}"
STATE_DIR="/tmp/.cc-compact-circuit-breaker"
STATE_FILE="$STATE_DIR/compaction-log"

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

NOW=$(date +%s)
ONE_HOUR_AGO=$((NOW - 3600))

# Clean old entries (older than 1 hour)
if [ -f "$STATE_FILE" ]; then
  awk -v cutoff="$ONE_HOUR_AGO" '$1 >= cutoff' "$STATE_FILE" > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
fi

# Count compactions in the last hour
RECENT_COUNT=$(wc -l < "$STATE_FILE" | tr -d ' ')

# Check minimum interval since last compaction
LAST_TIME=0
if [ -s "$STATE_FILE" ]; then
  LAST_TIME=$(tail -1 "$STATE_FILE")
fi
ELAPSED=$((NOW - LAST_TIME))

# Circuit breaker: block if too many compactions
if [ "$RECENT_COUNT" -ge "$MAX_PER_HOUR" ]; then
  echo "CIRCUIT BREAKER: $RECENT_COUNT compactions in the last hour (max: $MAX_PER_HOUR). Possible death spiral detected. Start a fresh session instead of compacting." >&2
  exit 2
fi

# Cooldown: block if too soon after last compaction
if [ "$ELAPSED" -lt "$MIN_INTERVAL" ] && [ "$LAST_TIME" -gt 0 ]; then
  echo "COOLDOWN: Last compaction was ${ELAPSED}s ago (min interval: ${MIN_INTERVAL}s). Wait before compacting again." >&2
  exit 2
fi

# Allow compaction and log it
echo "$NOW" >> "$STATE_FILE"
exit 0
