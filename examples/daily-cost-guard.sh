#!/usr/bin/env bash
# ================================================================
# daily-cost-guard.sh — Track per-day API-equivalent token cost
#                      and warn / block when the daily budget is
#                      exceeded
# ================================================================
# PURPOSE:
#   Anthropic's billing dashboard reflects with a multi-day delay,
#   so it cannot serve as a real-time spend guard. This hook reads
#   the actual usage data from the transcript file on every Stop
#   event, accumulates an API-equivalent cost estimate per day, and
#   warns at a soft threshold or signals when the daily budget is
#   exceeded.
#
#   Solves the May 2026 r/ClaudeAI report (735 points): an operator
#   left a 30-minute polling loop running overnight and woke up to
#   approximately $6,000 in cost because each polling iteration
#   re-sent an 800K-token conversation history without cache benefit
#   (loop interval > 5-minute cache TTL).
#
# TRIGGER: Stop
# MATCHER: ""
#
# WHY THIS MATTERS:
#   The hook runs once per turn at conversation end (zero per-turn
#   latency). It reads the transcript file to find the most recent
#   message.usage block, computes API-equivalent cost using
#   Sonnet 4.6 pricing, and writes a daily JSONL log. The daily
#   total accumulates across multiple sessions on the same date.
#
#   Subscription-plan users are not billed by API rate; the cost
#   estimate is a proxy for actual token consumption. Use it to
#   detect anomalous spend before the dashboard catches up.
#
# WHAT IT CHECKS:
#   1. Reads transcript_path from Stop hook input
#   2. Extracts the most recent message.usage block (input, output,
#      cache_read, cache_creation)
#   3. Computes Sonnet 4.6 API-equivalent cost for that turn
#   4. Appends the turn cost to today's JSONL log
#   5. Sums today's log to get the daily total
#   6. Warns at soft threshold, signals at daily limit
#
# OUTPUT:
#   Soft warning (exit 0) at WARN_THRESHOLD_USD.
#   Daily-limit-exceeded signal (exit 0 by default, exit 2 with
#   CC_DAILY_COST_BLOCK=1) at DAILY_LIMIT_USD.
#
# CONFIGURATION:
#   CC_DAILY_LIMIT_USD       — daily budget cap (default $5.00)
#   CC_DAILY_WARN_USD        — soft warning threshold (default $3.50)
#   CC_DAILY_COST_BLOCK      — set to "1" to exit 2 (signal context)
#                              when daily limit is exceeded; default
#                              is advisory (exit 0)
#   CC_DAILY_COST_LOG_DIR    — log directory (default
#                              ~/.claude/cost-log)
#   CC_DAILY_COST_MODEL      — pricing model (default "sonnet"; set
#                              to "opus" to use Opus 4.7 rates 5x
#                              higher)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/47049
#   r/ClaudeAI 2026-05-01 "$6000 overnight" report
# ================================================================

set -u

DAILY_LIMIT_USD="${CC_DAILY_LIMIT_USD:-5.00}"
WARN_THRESHOLD_USD="${CC_DAILY_WARN_USD:-3.50}"
LOG_DIR="${CC_DAILY_COST_LOG_DIR:-${HOME}/.claude/cost-log}"
MODEL="${CC_DAILY_COST_MODEL:-sonnet}"

# Pricing tables (USD per 1M tokens) as of 2026-05
case "$MODEL" in
    opus)
        # Opus 4.7: input $15 / output $75 / cache write $18.75 / cache read $1.50
        P_IN=15
        P_OUT=75
        P_CW=18.75
        P_CR=1.50
        ;;
    sonnet|*)
        # Sonnet 4.6: input $3 / output $15 / cache write $3.75 / cache read $0.30
        P_IN=3
        P_OUT=15
        P_CW=3.75
        P_CR=0.30
        ;;
esac

mkdir -p "${LOG_DIR}"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/${TODAY}.jsonl"

INPUT=$(cat)

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Extract the most recent message.usage block
LATEST_USAGE=$(grep -h '"usage"' "$TRANSCRIPT_PATH" 2>/dev/null \
    | tail -1 \
    | jq -r '.message.usage // empty' 2>/dev/null || true)

if [ -z "$LATEST_USAGE" ]; then
    exit 0
fi

TURN_INPUT=$(printf '%s' "$LATEST_USAGE" | jq -r '.input_tokens // 0' 2>/dev/null || echo 0)
TURN_OUTPUT=$(printf '%s' "$LATEST_USAGE" | jq -r '.output_tokens // 0' 2>/dev/null || echo 0)
TURN_CACHE_READ=$(printf '%s' "$LATEST_USAGE" | jq -r '.cache_read_input_tokens // 0' 2>/dev/null || echo 0)
TURN_CACHE_WRITE=$(printf '%s' "$LATEST_USAGE" | jq -r '.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)

COST_USD=$(awk -v i="$TURN_INPUT" -v o="$TURN_OUTPUT" -v cr="$TURN_CACHE_READ" -v cw="$TURN_CACHE_WRITE" \
              -v pi="$P_IN" -v po="$P_OUT" -v pcr="$P_CR" -v pcw="$P_CW" '
BEGIN {
    printf "%.6f\n", (i * pi + o * po + cw * pcw + cr * pcr) / 1000000
}')

printf '{"ts":"%s","turn_cost_usd":%s,"input":%s,"output":%s,"cache_read":%s,"cache_write":%s,"model":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COST_USD" "$TURN_INPUT" "$TURN_OUTPUT" "$TURN_CACHE_READ" "$TURN_CACHE_WRITE" "$MODEL" \
    >> "$LOG_FILE"

# Sum today's entries to get the daily total
TODAY_TOTAL=$(awk -F'"turn_cost_usd":' 'NF>1 {split($2, a, ","); sum += a[1]} END {printf "%.4f", sum+0}' "$LOG_FILE")

# Threshold checks
if awk "BEGIN {exit !($TODAY_TOTAL >= $DAILY_LIMIT_USD)}"; then
    cat >&2 <<EOF
🛑 daily-cost-guard: 当日累計が想定上限を超えました
  当日累計: \$${TODAY_TOTAL}
  想定上限: \$${DAILY_LIMIT_USD}
  ログ: ${LOG_FILE}
  原因の確認まで作業を止めることをお勧めします。
  Reference: https://github.com/anthropics/claude-code/issues/47049
EOF
    if [ "${CC_DAILY_COST_BLOCK:-0}" = "1" ]; then
        exit 2
    fi
elif awk "BEGIN {exit !($TODAY_TOTAL >= $WARN_THRESHOLD_USD)}"; then
    cat >&2 <<EOF
⚠ daily-cost-guard: 当日累計が警告閾値に達しました
  当日累計: \$${TODAY_TOTAL}
  警告閾値: \$${WARN_THRESHOLD_USD}
  想定上限: \$${DAILY_LIMIT_USD}
EOF
fi

exit 0
