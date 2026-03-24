#!/bin/bash
# ================================================================
# token-budget-guard.sh — Estimate and limit session token cost
# ================================================================
# PURPOSE:
#   Claude Code sessions can consume hundreds of dollars in tokens
#   without the user realizing it. This hook estimates cumulative
#   cost and warns/blocks when a budget threshold is exceeded.
#
# TRIGGER: PostToolUse  MATCHER: ""
#
# CONFIG:
#   CC_TOKEN_BUDGET=10    (warn at $10 estimated cost)
#   CC_TOKEN_BLOCK=50     (block at $50 estimated cost)
#
# Born from: https://github.com/anthropics/claude-code/issues/38029
#   "652k output tokens ($342) without user input"
# ================================================================

WARN_BUDGET="${CC_TOKEN_BUDGET:-10}"
BLOCK_BUDGET="${CC_TOKEN_BLOCK:-50}"
STATE="/tmp/cc-token-budget-$(echo "$PWD" | md5sum | cut -c1-8)"

# Estimate tokens from tool output size
INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)
OUTPUT_LEN=${#OUTPUT}

# Rough estimation: 1 token ≈ 4 chars, $15/M input + $75/M output for Opus
# This is approximate — actual costs depend on model and caching
TOKENS=$((OUTPUT_LEN / 4))

# Accumulate
TOTAL=0
[ -f "$STATE" ] && TOTAL=$(cat "$STATE" 2>/dev/null || echo 0)
TOTAL=$((TOTAL + TOKENS))
echo "$TOTAL" > "$STATE"

# Estimate cost (output tokens at $75/M for Opus)
# Using integer math: cost_cents = tokens * 75 / 10000
COST_CENTS=$((TOTAL * 75 / 10000))

if [ "$COST_CENTS" -ge "$((BLOCK_BUDGET * 100))" ]; then
    echo "BLOCKED: Estimated session cost ~\$${COST_CENTS%??}.${COST_CENTS: -2} exceeds \$$BLOCK_BUDGET budget." >&2
    echo "Reset: rm $STATE" >&2
    exit 2
fi

if [ "$COST_CENTS" -ge "$((WARN_BUDGET * 100))" ]; then
    echo "WARNING: Estimated session cost ~\$${COST_CENTS%??}.${COST_CENTS: -2} approaching \$$BLOCK_BUDGET limit." >&2
    echo "Consider using /compact or starting a new session." >&2
fi

exit 0
