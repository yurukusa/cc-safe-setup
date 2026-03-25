#!/bin/bash
# ================================================================
# response-budget-guard.sh — Track and limit tool calls per response
# ================================================================
# PURPOSE:
#   Prevents runaway tool call loops where Claude calls hundreds of
#   tools in a single response. Common in autonomous mode when the
#   agent enters a retry loop or tries to brute-force a solution.
#
#   Tracks tool calls per response cycle and warns after threshold.
#
# TRIGGER: PreToolUse  MATCHER: ""
#
# CONFIG:
#   CC_RESPONSE_TOOL_LIMIT=50  (warn after this many tool calls)
# ================================================================

LIMIT="${CC_RESPONSE_TOOL_LIMIT:-50}"
STATE="/tmp/cc-response-budget-$(echo "$PWD" | md5sum | cut -c1-8)"

# Read current count
COUNT=0
if [ -f "$STATE" ]; then
  COUNT=$(cat "$STATE")
fi

COUNT=$((COUNT + 1))
echo "$COUNT" > "$STATE"

if [ "$COUNT" -eq "$LIMIT" ]; then
  echo "WARNING: $COUNT tool calls in this response cycle." >&2
  echo "Consider whether you're in a retry loop." >&2
  echo "Reset: rm $STATE" >&2
fi

# Hard block at 2x limit to prevent truly runaway sessions
if [ "$COUNT" -gt $((LIMIT * 2)) ]; then
  echo "BLOCKED: $COUNT tool calls exceeds safety limit ($((LIMIT * 2)))." >&2
  echo "You appear to be in a loop. Stop and reassess." >&2
  exit 2
fi

exit 0
