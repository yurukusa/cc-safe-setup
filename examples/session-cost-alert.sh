#!/bin/bash
# session-cost-alert.sh — Alert when estimated session cost exceeds threshold
#
# Solves: #47049 — User lost £140 overnight without realizing costs were
#   accumulating. This hook estimates token cost per tool call and warns
#   when the session total exceeds a configurable threshold.
#
# How it works: PostToolUse hook that parses session_tokens from tool
#   results (when available) and estimates cost using Anthropic pricing.
#   Warns at $1 and blocks at $5 (configurable).
#
# CONFIG:
#   CC_COST_WARN=1     (warn at $1, default)
#   CC_COST_BLOCK=5    (block at $5, default)
#   CC_MODEL_COST=5    ($/M input tokens for Opus, default)
#
# TRIGGER: PostToolUse
# MATCHER: ""
# CATEGORY: cost-control

INPUT=$(cat)

WARN_THRESHOLD=${CC_COST_WARN:-1}
BLOCK_THRESHOLD=${CC_COST_BLOCK:-5}
COST_PER_M=${CC_MODEL_COST:-5}

COST_FILE="/tmp/cc-session-cost-${PPID}"

# Initialize
if [ ! -f "$COST_FILE" ]; then
    echo "0" > "$COST_FILE"
fi

# Try to extract token count from tool result
# Note: Not all tool results contain token info. This is a best-effort estimate.
TOKENS=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null | wc -c)
# Rough estimate: 1 char ≈ 0.3 tokens (for tool output going into context)
EST_TOKENS=$((TOKENS * 3 / 10))

# Add to running total
CURRENT=$(cat "$COST_FILE" 2>/dev/null || echo 0)
TOTAL=$((CURRENT + EST_TOKENS))
echo "$TOTAL" > "$COST_FILE"

# Estimate cost
COST=$(echo "scale=4; $TOTAL * $COST_PER_M / 1000000" | bc 2>/dev/null || echo "0")
COST_CENTS=$(echo "scale=0; $TOTAL * $COST_PER_M / 10000" | bc 2>/dev/null || echo "0")

# Check thresholds
BLOCK_CENTS=$(echo "scale=0; $BLOCK_THRESHOLD * 100" | bc 2>/dev/null || echo "500")
WARN_CENTS=$(echo "scale=0; $WARN_THRESHOLD * 100" | bc 2>/dev/null || echo "100")

if [ "$COST_CENTS" -ge "$BLOCK_CENTS" ] 2>/dev/null; then
    echo "BLOCKED: Estimated session cost \$${COST} exceeds \$${BLOCK_THRESHOLD} limit." >&2
    echo "  Estimated tokens used: ${TOTAL}" >&2
    echo "  Override: CC_COST_BLOCK=$((BLOCK_THRESHOLD * 2))" >&2
    exit 2
elif [ "$COST_CENTS" -ge "$WARN_CENTS" ] 2>/dev/null; then
    echo "WARNING: Estimated session cost \$${COST} approaching \$${BLOCK_THRESHOLD} limit." >&2
fi

exit 0
