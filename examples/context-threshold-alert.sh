#!/bin/bash
# context-threshold-alert.sh — Alert at configurable context usage thresholds
#
# Solves: No hook event for context usage thresholds (#40256).
#         Users want to be notified when context hits 50%, 75%, 90%
#         without waiting for the built-in context-monitor warnings.
#
# How it works: PostToolUse hook that reads the context percentage
#   from the tool output and triggers alerts at configurable thresholds.
#   Each threshold fires only once per session (tracked via temp file).
#
# CONFIG (environment variables):
#   CC_CONTEXT_WARN=50      # First warning at 50%
#   CC_CONTEXT_ALERT=75     # Alert at 75%
#   CC_CONTEXT_CRITICAL=90  # Critical at 90%
#   CC_CONTEXT_ACTION=log   # "log" (stderr only) or "block" (exit 2 at critical)
#
# TRIGGER: PostToolUse
# MATCHER: "" (all tools — checks context on every call)

INPUT=$(cat)

# Extract context percentage from tool output if available
CONTEXT_PCT=$(echo "$INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)

# If no context data in this tool call, try the session state
if [ -z "$CONTEXT_PCT" ]; then
    # Check if context-monitor data exists
    STATE_FILE="/tmp/cc-context-state-$$"
    [ -f "$STATE_FILE" ] && CONTEXT_PCT=$(cat "$STATE_FILE")
fi

[ -z "$CONTEXT_PCT" ] && exit 0

# Convert remaining % to used %
USED=$((100 - CONTEXT_PCT))

# Configurable thresholds
WARN=${CC_CONTEXT_WARN:-50}
ALERT=${CC_CONTEXT_ALERT:-75}
CRITICAL=${CC_CONTEXT_CRITICAL:-90}
ACTION=${CC_CONTEXT_ACTION:-log}

# Track which thresholds have fired (once per session)
FIRED_FILE="/tmp/cc-context-fired-${PPID}"

already_fired() {
    grep -q "^$1$" "$FIRED_FILE" 2>/dev/null
}

mark_fired() {
    echo "$1" >> "$FIRED_FILE"
}

# Check thresholds (highest first)
if [ "$USED" -ge "$CRITICAL" ] && ! already_fired "critical"; then
    echo "🔴 CRITICAL: Context usage at ${USED}% (threshold: ${CRITICAL}%)" >&2
    echo "  Consider running /compact or starting a new session" >&2
    mark_fired "critical"
    [ "$ACTION" = "block" ] && exit 2
elif [ "$USED" -ge "$ALERT" ] && ! already_fired "alert"; then
    echo "🟠 ALERT: Context usage at ${USED}% (threshold: ${ALERT}%)" >&2
    echo "  Commit work and prepare for compaction" >&2
    mark_fired "alert"
elif [ "$USED" -ge "$WARN" ] && ! already_fired "warn"; then
    echo "🟡 WARNING: Context usage at ${USED}% (threshold: ${WARN}%)" >&2
    mark_fired "warn"
fi

exit 0
