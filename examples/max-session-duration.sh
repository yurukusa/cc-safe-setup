#!/bin/bash
# ================================================================
# max-session-duration.sh — Warn when session exceeds time limit
# ================================================================
# PURPOSE:
#   Long autonomous sessions can rack up costs and context issues.
#   This hook tracks session duration and warns when it exceeds
#   a configurable limit, suggesting a new session.
#
# TRIGGER: PostToolUse  MATCHER: ""
#
# CONFIG:
#   CC_MAX_SESSION_HOURS=4  (warn after 4 hours)
# ================================================================

MAX_HOURS="${CC_MAX_SESSION_HOURS:-4}"
STATE="/tmp/cc-session-start-$(echo "$PWD" | md5sum | cut -c1-8)"

NOW=$(date +%s)

if [ ! -f "$STATE" ]; then
    echo "$NOW" > "$STATE"
    exit 0
fi

START=$(cat "$STATE" 2>/dev/null || echo "$NOW")
ELAPSED=$(( (NOW - START) / 3600 ))

if [ "$ELAPSED" -ge "$MAX_HOURS" ]; then
    MINS=$(( (NOW - START) / 60 ))
    echo "WARNING: Session running for ${ELAPSED}h ${MINS}m." >&2
    echo "Consider starting a new session to reset context." >&2
    echo "Reset timer: rm $STATE" >&2
fi

exit 0
