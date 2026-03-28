#!/bin/bash
# long-session-reminder.sh — Warn when session runs too long
#
# Solves: Sessions running for hours without user awareness, consuming
#         tokens and potentially drifting from the original task.
#         Related: #37917 (usage explosion), #38335 (session limits)
#
# How it works: Tracks session start time via a flag file. On every
#   tool use, checks elapsed time. Warns at threshold (default 2 hours).
#
# The warning is informational only (exit 0) — it doesn't block anything.
# Change to exit 2 at the bottom to enforce a hard stop.
#
# TRIGGER: PostToolUse  MATCHER: ""
# (empty matcher = fires on every tool use)

INPUT=$(cat)

FLAG="$HOME/.claude/session-start-time"
THRESHOLD_MINUTES=${CC_SESSION_LIMIT_MINUTES:-120}

# Create flag file on first invocation
if [ ! -f "$FLAG" ]; then
    date +%s > "$FLAG"
    exit 0
fi

START=$(cat "$FLAG" 2>/dev/null)
[[ -z "$START" ]] && exit 0

NOW=$(date +%s)
ELAPSED_MINUTES=$(( (NOW - START) / 60 ))

if [ "$ELAPSED_MINUTES" -ge "$THRESHOLD_MINUTES" ]; then
    HOURS=$((ELAPSED_MINUTES / 60))
    MINS=$((ELAPSED_MINUTES % 60))
    echo "⏰ Session running for ${HOURS}h${MINS}m (threshold: ${THRESHOLD_MINUTES}min)" >&2
    echo "  Consider: compact, commit progress, or end session." >&2
    # Only warn once every 30 minutes (not every tool call)
    LAST_WARN="$HOME/.claude/session-last-warn"
    if [ -f "$LAST_WARN" ]; then
        LAST=$(cat "$LAST_WARN")
        SINCE_WARN=$(( (NOW - LAST) / 60 ))
        [ "$SINCE_WARN" -lt 30 ] && exit 0
    fi
    echo "$NOW" > "$LAST_WARN"
fi

exit 0
