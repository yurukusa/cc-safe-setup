#!/bin/bash
# ================================================================
# cost-tracker.sh — Estimate session token cost
# ================================================================
# PURPOSE:
#   Claude Code doesn't show token costs. This hook tracks
#   tool calls and estimates cumulative cost, warning at thresholds.
#
# TRIGGER: PostToolUse
# MATCHER: ""
#
# HOW IT WORKS:
#   Counts tool calls as a proxy for token usage.
#   Average tool call ≈ 2K tokens input + 1K output.
#   Opus: $15/M input, $75/M output
#   Sonnet: $3/M input, $15/M output
#
# CONFIGURATION:
#   CC_COST_MODEL=opus   (default) or sonnet
#   CC_COST_WARN=1.00    warn at $1 (default)
#   CC_COST_BLOCK=5.00   warn at $5 (default, doesn't block)
# ================================================================

COUNTER_FILE="/tmp/cc-cost-tracker-calls"
LAST_WARN="/tmp/cc-cost-tracker-warned"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

MODEL="${CC_COST_MODEL:-opus}"
WARN="${CC_COST_WARN:-1.00}"
BLOCK="${CC_COST_BLOCK:-5.00}"

# Estimate: ~2K input + ~1K output tokens per tool call
if [ "$MODEL" = "opus" ]; then
    # Opus: $15/M in, $75/M out → ~$0.105 per tool call
    COST=$(echo "scale=2; $COUNT * 0.105" | bc 2>/dev/null || echo "0")
else
    # Sonnet: $3/M in, $15/M out → ~$0.021 per tool call
    COST=$(echo "scale=2; $COUNT * 0.021" | bc 2>/dev/null || echo "0")
fi

# Graduated warnings (with cooldown)
WARNED=$(cat "$LAST_WARN" 2>/dev/null || echo "0")

if [ "$(echo "$COST >= $BLOCK" | bc 2>/dev/null)" = "1" ] && [ "$WARNED" != "block" ]; then
    echo "COST: ~\$${COST} estimated ($COUNT tool calls, $MODEL)" >&2
    echo "Consider finishing current task and compacting." >&2
    echo "block" > "$LAST_WARN"
elif [ "$(echo "$COST >= $WARN" | bc 2>/dev/null)" = "1" ] && [ "$WARNED" = "0" ]; then
    echo "COST: ~\$${COST} estimated ($COUNT tool calls, $MODEL)" >&2
    echo "warn" > "$LAST_WARN"
fi

exit 0
