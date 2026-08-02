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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-work-hours-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [work-hours-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
