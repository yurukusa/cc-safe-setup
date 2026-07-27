#!/bin/bash
# session-health-monitor.sh — Monitor session health metrics
#
# Solves: Long-running sessions degrade silently — context fills up,
#         tool calls slow down, errors accumulate. No visibility into
#         session health until it's too late.
#
# How it works: PreToolUse hook that tracks session metrics:
#   - Tool call count (proxy for context usage)
#   - Error rate (consecutive failures)
#   - Session duration
#   Warns at configurable thresholds.
#
# TRIGGER: PreToolUse
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-health-monitor.sh" }]
#     }]
#   }
# }

STATE="/tmp/cc-health-$$"

# Initialize on first call
if [ ! -f "$STATE" ]; then
    echo "start=$(date +%s) calls=0 errors=0" > "$STATE"
fi

# Read current state
eval $(cat "$STATE")
calls=$((calls + 1))

# Update state
echo "start=$start calls=$calls errors=$errors" > "$STATE"

# Check thresholds
DURATION=$(( ($(date +%s) - start) / 60 ))

if [ "$calls" -eq 50 ]; then
    echo "ℹ Session health: 50 tool calls, ${DURATION}m elapsed." >&2
fi

if [ "$calls" -eq 150 ]; then
    echo "⚠ Session health: 150 tool calls, ${DURATION}m elapsed. Context may be getting full." >&2
    echo "Consider saving state and starting a fresh session." >&2
fi

if [ "$calls" -ge 250 ] && [ $((calls % 50)) -eq 0 ]; then
    echo "🔴 Session health: $calls tool calls, ${DURATION}m elapsed. Performance may be degraded." >&2
fi

# Duration warning
if [ "$DURATION" -ge 120 ] && [ $((calls % 100)) -eq 0 ]; then
    echo "⏰ Session running for ${DURATION}m. Long sessions accumulate context drift." >&2
fi

exit 0
