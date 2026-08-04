#!/bin/bash
# quota-anomaly-detector.sh — alert when token consumption rate diverges from your personal baseline
#
# Why: The Pro Max quota anomaly cluster (#16157 / #38335 / #45756 / #41788 / #29579
#      / #19673 / cumulative ~1,600 reactions) reports the same operator-side symptom:
#      the quota empties materially faster than the same workflow used to consume it,
#      sometimes within minutes of the session starting. Four issues name a runtime
#      version or date boundary (2026-03-23 / v2.1.89 / v2.1.100 / 2.1.1) so the
#      shift is version-correlated.
#
#      cache-creation-drift-detector.sh catches the *per-request* server-side
#      inflation documented in #46917, but it cannot see the cross-request picture:
#      a session that fires 40 small requests in 10 minutes burns the same quota as
#      one large request, and only the rolling rate exposes it. This hook fills that
#      gap by tracking total tokens-per-minute against a personal trailing baseline.
#
#      Composes with cache-creation-drift-detector (per-request) and the existing
#      session-quota-tracker.sh (raw tool-call count, no token weight).
#
# Event: PostToolUse  MATCHER: "" (all tools)
# Action: Sum input_tokens + output_tokens + cache_read_input_tokens +
#         cache_creation_input_tokens from the PostToolUse payload (or last
#         assistant turn in the transcript as fallback). Append a timestamped
#         sample to a rolling JSONL log. Compute the operator's tokens-per-minute
#         over the trailing window. If the current window's rate exceeds the
#         trailing baseline by a configurable multiplier, emit a one-line stderr
#         warning. Advisory only (exit 0); does not block.
#
# Configuration (all optional):
#   CC_QUOTA_ANOMALY_LOG          Log path (default: ~/.cache/cc-safe-setup/quota-anomaly.jsonl)
#   CC_QUOTA_ANOMALY_THRESHOLD    Multiplier for alert (default: 1.5 = 50% above baseline rate)
#   CC_QUOTA_ANOMALY_MIN_HISTORY  Minimum samples before alerting (default: 30)
#   CC_QUOTA_ANOMALY_WINDOW_MIN   Current-rate window in minutes (default: 10)
#   CC_QUOTA_ANOMALY_BASELINE_MIN Baseline window in minutes (default: 1440 = 24h)
#   CC_QUOTA_ANOMALY_SILENT       Set to "1" to suppress stderr (still logs)
#
# Inspect the log:
#   tail -50 ~/.cache/cc-safe-setup/quota-anomaly.jsonl
#   jq -s 'map(.total) | add' ~/.cache/cc-safe-setup/quota-anomaly.jsonl
#
# The registration was missing from this header. The installer reads TRIGGER
# and MATCHER from here and falls back to PreToolUse / Bash when both are
# absent, so this hook was being registered at a moment where the field it
# reads is always empty: it installed, it appeared in the settings, and it
# did nothing. Measured 2026-08-04 across examples/: 14 files were like this.
# TRIGGER: PostToolUse
# MATCHER: ""

set -u

LOG="${CC_QUOTA_ANOMALY_LOG:-${HOME}/.cache/cc-safe-setup/quota-anomaly.jsonl}"
THRESHOLD="${CC_QUOTA_ANOMALY_THRESHOLD:-1.5}"
MIN_HISTORY="${CC_QUOTA_ANOMALY_MIN_HISTORY:-30}"
WINDOW_MIN="${CC_QUOTA_ANOMALY_WINDOW_MIN:-10}"
BASELINE_MIN="${CC_QUOTA_ANOMALY_BASELINE_MIN:-1440}"
SILENT="${CC_QUOTA_ANOMALY_SILENT:-0}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT=$(cat)

extract_total() {
  # $1 = jq path prefix to usage object
  local prefix="$1"
  printf '%s' "$INPUT" | jq -r --arg p "$prefix" '
    def num(x): if (x | type) == "number" then x else 0 end;
    ($p | split(".") | map(select(length > 0))) as $path |
    (getpath($path)) as $u |
    if $u == null then empty
    else
      (num($u.input_tokens) + num($u.output_tokens) +
       num($u.cache_read_input_tokens) + num($u.cache_creation_input_tokens))
    end
  ' 2>/dev/null
}

# Try PostToolUse payload first.
TOTAL=$(extract_total ".tool_response.usage")

# Fallback: read the last assistant turn's usage from the transcript.
if [ -z "$TOTAL" ] || [ "$TOTAL" = "0" ]; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
    LAST_USAGE_LINE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"usage"' || true)
    if [ -n "$LAST_USAGE_LINE" ]; then
      TOTAL=$(printf '%s' "$LAST_USAGE_LINE" | jq -r '
        def num(x): if (x | type) == "number" then x else 0 end;
        (.message.usage // .usage // null) as $u |
        if $u == null then empty
        else
          (num($u.input_tokens) + num($u.output_tokens) +
           num($u.cache_read_input_tokens) + num($u.cache_creation_input_tokens))
        end
      ' 2>/dev/null)
    fi
  fi
fi

# No usable measurement.
if [ -z "$TOTAL" ] || [ "$TOTAL" = "0" ] || [ "$TOTAL" = "null" ]; then
  exit 0
fi

# Validate positive integer.
case "$TOTAL" in
  ''|*[!0-9]*) exit 0 ;;
esac

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
NOW_EPOCH=$(date -u +%s)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Append sample.
printf '{"ts":"%s","epoch":%s,"session":"%s","total":%s}\n' \
  "$TS" "$NOW_EPOCH" "$SESSION_ID" "$TOTAL" >> "$LOG"

# Need MIN_HISTORY samples before trusting the baseline.
SAMPLE_COUNT=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
SAMPLE_COUNT="${SAMPLE_COUNT:-0}"
if [ "$SAMPLE_COUNT" -lt "$MIN_HISTORY" ]; then
  exit 0
fi

# Compute current window sum and baseline window sum.
WINDOW_CUTOFF=$((NOW_EPOCH - WINDOW_MIN * 60))
BASELINE_CUTOFF=$((NOW_EPOCH - BASELINE_MIN * 60))

# Read once, compute both sums and counts.
SUMS=$(awk -v wc="$WINDOW_CUTOFF" -v bc="$BASELINE_CUTOFF" '
  /"epoch":/ {
    # Extract epoch and total via simple field parse (matches our writer format).
    match($0, /"epoch":[0-9]+/)
    e = substr($0, RSTART+8, RLENGTH-8) + 0
    match($0, /"total":[0-9]+/)
    t = substr($0, RSTART+8, RLENGTH-8) + 0
    if (e >= bc) {
      bs += t; bn++
      if (e >= wc) { ws += t; wn++ }
    }
  }
  END { printf "%d %d %d %d", ws, wn, bs, bn }
' "$LOG" 2>/dev/null)

WINDOW_SUM=$(echo "$SUMS" | awk '{print $1}')
WINDOW_N=$(echo "$SUMS" | awk '{print $2}')
BASELINE_SUM=$(echo "$SUMS" | awk '{print $3}')
BASELINE_N=$(echo "$SUMS" | awk '{print $4}')

# Need enough activity in both windows.
if [ "${WINDOW_N:-0}" -lt 2 ] || [ "${BASELINE_N:-0}" -lt "$MIN_HISTORY" ]; then
  exit 0
fi

# Compute rates: tokens per minute in each window.
RATIO=$(awk -v ws="$WINDOW_SUM" -v wm="$WINDOW_MIN" \
            -v bs="$BASELINE_SUM" -v bm="$BASELINE_MIN" '
  BEGIN {
    wr = ws / wm
    br = bs / bm
    if (br > 0) printf "%.3f", wr / br; else print "0"
  }')
EXCEEDS=$(awk -v r="$RATIO" -v t="$THRESHOLD" 'BEGIN { print (r > t) ? 1 : 0 }')

if [ "$EXCEEDS" = "1" ] && [ "$SILENT" != "1" ]; then
  WIN_RATE=$(awk -v ws="$WINDOW_SUM" -v wm="$WINDOW_MIN" 'BEGIN { printf "%d", ws/wm }')
  BASE_RATE=$(awk -v bs="$BASELINE_SUM" -v bm="$BASELINE_MIN" 'BEGIN { printf "%d", bs/bm }')
  PCT=$(awk -v r="$RATIO" 'BEGIN { printf "%d", (r - 1) * 100 }')
  echo "NOTICE: token consumption rate ~${WIN_RATE} tok/min over last ${WINDOW_MIN}min is ${PCT}% above your ${BASELINE_MIN}min baseline (~${BASE_RATE} tok/min)." >&2
  echo "        Pro Max quota anomaly cluster: anthropics/claude-code #16157 / #38335 / #45756." >&2
  echo "        Inspect ${LOG} or set CC_QUOTA_ANOMALY_SILENT=1 to suppress." >&2
fi

exit 0
