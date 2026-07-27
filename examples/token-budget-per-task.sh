#!/bin/bash
# token-budget-per-task.sh — Track and warn on per-task token usage
#
# Solves: A single task consuming the entire daily token budget.
#         Without visibility into per-task costs, users don't realize
#         until they hit rate limits.
#
# How it works: PostToolUse hook that estimates tokens per tool call
#   and tracks cumulative usage. Warns at configurable thresholds.
#
# CONFIG:
#   CC_TOKEN_WARN_THRESHOLD=50000 (warn at this many tokens)
#   CC_TOKEN_BLOCK_THRESHOLD=200000 (block at this many tokens)
#
# TRIGGER: PostToolUse
# MATCHER: ""

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

COUNTER_FILE="/tmp/claude-token-budget-${PPID:-0}"
WARN="${CC_TOKEN_WARN_THRESHOLD:-50000}"
BLOCK="${CC_TOKEN_BLOCK_THRESHOLD:-200000}"

# Rough token estimates per tool call
case "$TOOL" in
    Bash) TOKENS=500 ;;
    Read) TOKENS=2000 ;;
    Edit|Write) TOKENS=1000 ;;
    Glob|Grep) TOKENS=300 ;;
    Agent) TOKENS=5000 ;;
    *) TOKENS=200 ;;
esac

# Add result size estimate
RESULT_LEN=$(echo "$INPUT" | jq -r '.tool_result // "" | length' 2>/dev/null || echo 0)
TOKENS=$((TOKENS + RESULT_LEN / 4))  # ~4 chars per token

# Update counter
TOTAL=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
TOTAL=$((TOTAL + TOKENS))
echo "$TOTAL" > "$COUNTER_FILE"

if [ "$TOTAL" -ge "$BLOCK" ]; then
    echo "TOKEN BUDGET: ~${TOTAL} tokens used in this task (limit: ${BLOCK})." >&2
    echo "Consider breaking this into smaller tasks." >&2
    # Warning only — change to exit 2 to block
elif [ "$TOTAL" -ge "$WARN" ]; then
    echo "TOKEN BUDGET: ~${TOTAL} tokens used (warning threshold: ${WARN})." >&2
fi

exit 0
