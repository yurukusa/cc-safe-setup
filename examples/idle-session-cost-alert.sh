#!/bin/bash
# idle-session-cost-alert.sh — Warn when session has been idle too long
# An idle session can still consume tokens via background processes.
# Incident: #50389 — Idle session consumed 18% usage limit over 2 hours with zero user input.
#
# This hook runs on Notification events and warns if the session has been
# idle for more than 5 minutes, reminding the user to exit if not actively working.
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/idle-session-cost-alert.sh" }]
#     }]
#   }
# }

INPUT=$(cat)

# Track last activity timestamp
IDLE_FILE="/tmp/claude-idle-tracker-$$"
CURRENT_TIME=$(date +%s)

if [ -f "$IDLE_FILE" ]; then
    LAST_ACTIVE=$(cat "$IDLE_FILE")
    IDLE_SECONDS=$((CURRENT_TIME - LAST_ACTIVE))

    if [ "$IDLE_SECONDS" -gt 300 ]; then
        IDLE_MINUTES=$((IDLE_SECONDS / 60))
        echo "WARNING: Session idle for ${IDLE_MINUTES} minutes. Idle sessions can consume tokens via background processes (#50389). Consider exiting if not actively working." >&2
    fi
fi

echo "$CURRENT_TIME" > "$IDLE_FILE"
exit 0
