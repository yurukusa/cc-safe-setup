#!/bin/bash
# ================================================================
# session-duration-guard.sh — Warn on long-running sessions
# ================================================================
# PURPOSE:
#   Model quality degrades in very long sessions due to context
#   accumulation, compaction artifacts, and attention dilution.
#   This hook warns at configurable thresholds and suggests
#   saving state + starting fresh.
#
#   Based on 700+ hours of autonomous operation experience.
#
# TRIGGER: PostToolUse
# MATCHER: ""  (all tools)
#
# CONFIG:
#   CC_SESSION_WARN_HOURS=2  (warn after 2 hours, default)
#   CC_SESSION_CRITICAL_HOURS=4  (critical after 4 hours, default)
# ================================================================

MARKER="/tmp/cc-session-start-$$"
WARN_HOURS="${CC_SESSION_WARN_HOURS:-2}"
CRITICAL_HOURS="${CC_SESSION_CRITICAL_HOURS:-4}"

# Create marker on first run
if [ ! -f "$MARKER" ]; then
    date +%s > "$MARKER"
    exit 0
fi

# Check every 50 tool calls (not every call)
COUNTER="/tmp/cc-duration-counter-$$"
COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER"
[ $((COUNT % 50)) -ne 0 ] && exit 0

START=$(cat "$MARKER" 2>/dev/null || echo 0)
NOW=$(date +%s)
ELAPSED=$(( (NOW - START) / 3600 ))
ELAPSED_MIN=$(( (NOW - START) / 60 ))

if [ "$ELAPSED" -ge "$CRITICAL_HOURS" ]; then
    echo "⚠ CRITICAL: Session running for ${ELAPSED_MIN} minutes (${ELAPSED}+ hours)." >&2
    echo "  Model quality typically degrades after ${CRITICAL_HOURS} hours." >&2
    echo "  Save your state and start a new session: /compact then resume later." >&2
elif [ "$ELAPSED" -ge "$WARN_HOURS" ]; then
    echo "NOTE: Session running for ${ELAPSED_MIN} minutes. Consider saving state." >&2
fi

exit 0
