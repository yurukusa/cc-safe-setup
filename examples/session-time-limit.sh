#!/bin/bash
# session-time-limit.sh — Warn when session exceeds time limit
#
# Prevents: Unbounded autonomous sessions that consume excessive tokens.
#           Default: warn at 2 hours, configurable via CC_SESSION_LIMIT_HOURS.
#
# TRIGGER: PostToolUse
# MATCHER: ""

INPUT=$(cat)

# Track session start
MARKER="/tmp/cc-session-start-$$"
NOW=$(date +%s)

if [ ! -f "$MARKER" ]; then
  echo "$NOW" > "$MARKER"
  exit 0
fi

START=$(cat "$MARKER")
ELAPSED=$(( (NOW - START) / 60 ))  # minutes
LIMIT_HOURS="${CC_SESSION_LIMIT_HOURS:-2}"
LIMIT_MIN=$((LIMIT_HOURS * 60))
WARN_MIN=$((LIMIT_MIN * 3 / 4))  # warn at 75%

if [ "$ELAPSED" -ge "$LIMIT_MIN" ]; then
  echo "SESSION TIME LIMIT: ${ELAPSED}min elapsed (limit: ${LIMIT_HOURS}h)." >&2
  echo "  Consider saving work and starting a new session." >&2
elif [ "$ELAPSED" -ge "$WARN_MIN" ]; then
  echo "[Session: ${ELAPSED}min / ${LIMIT_HOURS}h limit]" >&2
fi

exit 0
