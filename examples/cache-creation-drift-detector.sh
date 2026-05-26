#!/bin/bash
# cache-creation-drift-detector.sh — alert when per-request cache_creation drifts above baseline
#
# Why: Issue #46917 documents that Claude Code v2.1.100+ inflates
#      cache_creation_input_tokens by ~20K vs v2.1.98 on the SAME payload, server-side.
#      This is the load-bearing reproduction in a ~2,200-reaction Pro Max quota
#      anomaly cluster (#16157 / #38335 / #46917 / #45756 / #29579 / #41788 / #13585
#      / #23706 / #16856 / #19673). Four issues name a runtime version or date
#      boundary (2026-03-23 / v2.1.89 / v2.1.100 / 2.1.1), so the inflation is
#      version-correlated and operator-side measurable.
#
#      The existing cache-tier-logger.sh logs every event but never computes
#      drift — operators have to write awk pipelines to spot the regression.
#      This hook does the drift computation inline and surfaces a one-line
#      stderr warning when the current request's cache_creation exceeds the
#      trailing-window mean by a configurable multiplier.
#
# Event: PostToolUse  MATCHER: "" (all tools)
# Action: Read cache_creation_input_tokens from the PostToolUse payload (or the
#         last assistant turn in the transcript as fallback). Append to a rolling
#         JSONL log. Compute the mean of the last N nonzero samples. If the
#         current value exceeds threshold * mean, emit a warning to stderr.
#         Advisory only (exit 0); does not block.
#
# Configuration (all optional):
#   CC_CACHE_DRIFT_LOG          Log path (default: ~/.cache/cc-safe-setup/cache-creation-drift.jsonl)
#   CC_CACHE_DRIFT_THRESHOLD    Multiplier for alert (default: 1.25 = 25% above mean)
#   CC_CACHE_DRIFT_MIN_HISTORY  Minimum samples before alerting (default: 20)
#   CC_CACHE_DRIFT_WINDOW       Trailing window size for mean (default: 200 samples)
#   CC_CACHE_DRIFT_SILENT       Set to "1" to suppress stderr (still logs)
#
# Inspect the log:
#   tail -50 ~/.cache/cc-safe-setup/cache-creation-drift.jsonl
#   jq -s 'map(.cc_tokens) | add / length' ~/.cache/cc-safe-setup/cache-creation-drift.jsonl

set -u

LOG="${CC_CACHE_DRIFT_LOG:-${HOME}/.cache/cc-safe-setup/cache-creation-drift.jsonl}"
THRESHOLD="${CC_CACHE_DRIFT_THRESHOLD:-1.25}"
MIN_HISTORY="${CC_CACHE_DRIFT_MIN_HISTORY:-20}"
WINDOW="${CC_CACHE_DRIFT_WINDOW:-200}"
SILENT="${CC_CACHE_DRIFT_SILENT:-0}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT=$(cat)

# Extract cache_creation from the PostToolUse payload (path varies by tool).
CC_TOKENS=$(printf '%s' "$INPUT" | jq -r '.tool_response.usage.cache_creation_input_tokens // empty' 2>/dev/null)

# Fallback: read the last assistant turn's usage from the transcript.
if [ -z "$CC_TOKENS" ]; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
    LAST_USAGE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"usage"' || true)
    if [ -n "$LAST_USAGE" ]; then
      CC_TOKENS=$(printf '%s' "$LAST_USAGE" | \
        jq -r '.message.usage.cache_creation_input_tokens // .usage.cache_creation_input_tokens // empty' 2>/dev/null)
    fi
  fi
fi

# No usable measurement — exit quietly (this is the common case for many tools).
if [ -z "$CC_TOKENS" ] || [ "$CC_TOKENS" = "0" ] || [ "$CC_TOKENS" = "null" ]; then
  exit 0
fi

# Validate the value is a positive integer.
case "$CC_TOKENS" in
  ''|*[!0-9]*) exit 0 ;;
esac

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Append this sample to the rolling log as a JSONL line.
printf '{"ts":"%s","session":"%s","cc_tokens":%s}\n' "$TS" "$SESSION_ID" "$CC_TOKENS" >> "$LOG"

# How many historical samples do we have so far? (Includes the line we just appended.)
SAMPLE_COUNT=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
SAMPLE_COUNT="${SAMPLE_COUNT:-0}"

# Need at least MIN_HISTORY samples before we trust the baseline.
if [ "$SAMPLE_COUNT" -lt "$MIN_HISTORY" ]; then
  exit 0
fi

# Compute the mean of the trailing window (excluding the just-written sample).
# We exclude the current sample so the alert compares "this" against "the past".
TAIL_LINES=$((WINDOW + 1))
MEAN=$(tail -n "$TAIL_LINES" "$LOG" 2>/dev/null | head -n -1 | \
  jq -s 'if length > 0 then (map(.cc_tokens) | add / length) else 0 end' 2>/dev/null)

# If the baseline mean is invalid or zero, skip (defensive).
if [ -z "$MEAN" ] || [ "$MEAN" = "0" ] || [ "$MEAN" = "null" ]; then
  exit 0
fi

# Compute ratio = CC_TOKENS / MEAN. Use awk because bash lacks float arithmetic.
RATIO=$(awk -v c="$CC_TOKENS" -v m="$MEAN" 'BEGIN { if (m > 0) printf "%.3f", c/m; else print "0" }')
EXCEEDS=$(awk -v r="$RATIO" -v t="$THRESHOLD" 'BEGIN { print (r > t) ? 1 : 0 }')

if [ "$EXCEEDS" = "1" ] && [ "$SILENT" != "1" ]; then
  # Format the baseline mean as an integer for the human-readable output.
  MEAN_INT=$(awk -v m="$MEAN" 'BEGIN { printf "%d", m }')
  PCT=$(awk -v r="$RATIO" 'BEGIN { printf "%d", (r - 1) * 100 }')
  echo "NOTICE: cache_creation_input_tokens=${CC_TOKENS} is ${PCT}% above your trailing-${WINDOW}-sample baseline (~${MEAN_INT})." >&2
  echo "        Possible version-correlated server-side inflation (see anthropics/claude-code #46917)." >&2
  echo "        Inspect ${LOG} or run: jq -s 'map(.cc_tokens) | add/length' ${LOG}" >&2
fi

exit 0
