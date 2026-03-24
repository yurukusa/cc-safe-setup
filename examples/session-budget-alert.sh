#!/bin/bash
# session-budget-alert.sh — Show session budget status on start
# TRIGGER: SessionStart  MATCHER: ""
# Reads from token budget state if available
STATE_PREFIX="/tmp/cc-token-budget-"
STATES=$(ls ${STATE_PREFIX}* 2>/dev/null)
if [ -n "$STATES" ]; then
    for f in $STATES; do
        TOKENS=$(cat "$f" 2>/dev/null || echo 0)
        COST=$((TOKENS * 75 / 10000))
        if [ "$COST" -gt 100 ]; then
            echo "NOTE: Previous session spent ~\$${COST%??}.${COST: -2} in estimated tokens." >&2
        fi
    done
fi
exit 0
