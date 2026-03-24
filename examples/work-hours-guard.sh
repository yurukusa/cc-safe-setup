#!/bin/bash
# ================================================================
# work-hours-guard.sh — Restrict risky operations outside work hours
# ================================================================
# PURPOSE:
#   During off-hours (nights/weekends), block high-risk operations
#   that a human should review. Safe read-only ops still pass.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# CONFIGURATION:
#   CC_WORK_START=9   (default: 9am)
#   CC_WORK_END=18    (default: 6pm)
#   CC_WORK_DAYS=12345 (default: Mon-Fri, 1=Mon 7=Sun)
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

HOUR=$(date +%H)
DOW=$(date +%u)  # 1=Monday, 7=Sunday

START="${CC_WORK_START:-9}"
END="${CC_WORK_END:-18}"
DAYS="${CC_WORK_DAYS:-12345}"

# Check if within work hours
IN_HOURS=0
if echo "$DAYS" | grep -q "$DOW"; then
    if [ "$HOUR" -ge "$START" ] && [ "$HOUR" -lt "$END" ]; then
        IN_HOURS=1
    fi
fi

# During work hours, allow everything
[ "$IN_HOURS" = "1" ] && exit 0

# Outside work hours, block high-risk operations
if echo "$COMMAND" | grep -qE 'git\s+push|deploy|npm\s+publish|docker\s+push'; then
    echo "BLOCKED: High-risk operation outside work hours ($HOUR:00)." >&2
    echo "Command: $COMMAND" >&2
    echo "Work hours: ${START}:00-${END}:00 (days: $DAYS)" >&2
    exit 2
fi

exit 0
