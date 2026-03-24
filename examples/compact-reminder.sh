#!/bin/bash
# ================================================================
# compact-reminder.sh — Remind to /compact when context is low
# ================================================================
# PURPOSE:
#   After Claude responds (Stop event), check how many tool calls
#   have been made in the session. If the count exceeds a threshold,
#   suggest running /compact to free up context space.
#
# TRIGGER: Stop  MATCHER: ""
#
# CONFIG:
#   CC_COMPACT_THRESHOLD=100  (suggest after 100 tool calls)
# ================================================================

THRESHOLD="${CC_COMPACT_THRESHOLD:-100}"
STATE="/tmp/cc-tool-count-$(echo "$PWD" | md5sum | cut -c1-8)"

# Increment counter
COUNT=1
[ -f "$STATE" ] && COUNT=$(($(cat "$STATE") + 1))
echo "$COUNT" > "$STATE"

if [ "$COUNT" -eq "$THRESHOLD" ]; then
    echo "" >&2
    echo "NOTE: $COUNT tool calls in this session." >&2
    echo "Consider running /compact to free context space." >&2
    echo "Reset counter: rm $STATE" >&2
fi

# Repeat reminder every 50 calls after threshold
if [ "$COUNT" -gt "$THRESHOLD" ] && [ $(( (COUNT - THRESHOLD) % 50 )) -eq 0 ]; then
    echo "REMINDER: $COUNT tool calls. /compact recommended." >&2
fi

exit 0
