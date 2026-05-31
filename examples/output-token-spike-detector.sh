#!/bin/bash
# output-token-spike-detector.sh — alert when per-request output_tokens spikes above baseline
#
# Why: Cluster 23 candidate (Opus 4.8 effort-budget regression) documents that
#      Opus 4.8 under effort=medium can spend 40-50k output tokens on hidden
#      thinking for a routine coding turn — Issue #64153 anchor (46,433 output
#      tokens / 22m 43s of thinking on a small rename-impact scan, transcript
#      stop_reason=end_turn so this completed normally, not a retry / not an
#      API 400). The reporter explicitly compares: Opus 4.6 / Opus 4.7 do NOT
#      show this magnitude for comparable routine work. Five independent filings
#      so far (#64153 / #64152 / #64143 / #64102 / #63455).
#
#      This is structurally distinct from Cluster 4 (Pro Max quota) which is
#      server-side cache_creation_input_tokens inflation — Cluster 23 candidate
#      is output_tokens magnitude. #64153's transcript shows cache_creation
#      4,054 vs output 46,433, the opposite ratio of Cluster 4's signature.
#      So Cluster 4's hooks (cache-creation-drift-detector etc.) do not catch
#      Cluster 23 candidate directly.
#
#      Routine coding turns should sit at 1-5k output tokens; 10× above that is
#      the operator-side signal that the model is burning hidden-thinking budget
#      out of proportion to the visible work. This hook emits a one-line stderr
#      warning when the current request's output_tokens exceeds the trailing-
#      window mean by a configurable multiplier (default 3.0, higher than the
#      cache-creation drift threshold because output_tokens naturally varies
#      more across turns).
#
# Event: PostToolUse  MATCHER: "" (all tools)
# Action: Read output_tokens from the PostToolUse payload (or the last assistant
#         turn in the transcript as fallback). Append to a rolling JSONL log.
#         Compute the mean of the last N nonzero samples. If the current value
#         exceeds threshold * mean, emit a warning to stderr with the Opus 4.7
#         fallback path. Advisory only (exit 0); does not block.
#
# Configuration (all optional):
#   CC_OUTPUT_SPIKE_LOG          Log path (default: ~/.cache/cc-safe-setup/output-token-spike.jsonl)
#   CC_OUTPUT_SPIKE_THRESHOLD    Multiplier for alert (default: 3.0 = 3× above mean)
#   CC_OUTPUT_SPIKE_MIN_HISTORY  Minimum samples before alerting (default: 20)
#   CC_OUTPUT_SPIKE_WINDOW       Trailing window size for mean (default: 200 samples)
#   CC_OUTPUT_SPIKE_FLOOR        Absolute minimum (default: 10000) — never alert below this
#                                even at threshold ratio, to suppress noise on small turns
#   CC_OUTPUT_SPIKE_SILENT       Set to "1" to suppress stderr (still logs)
#
# Inspect the log:
#   tail -50 ~/.cache/cc-safe-setup/output-token-spike.jsonl
#   jq -s 'map(.out_tokens) | add / length' ~/.cache/cc-safe-setup/output-token-spike.jsonl

set -u

LOG="${CC_OUTPUT_SPIKE_LOG:-${HOME}/.cache/cc-safe-setup/output-token-spike.jsonl}"
THRESHOLD="${CC_OUTPUT_SPIKE_THRESHOLD:-3.0}"
MIN_HISTORY="${CC_OUTPUT_SPIKE_MIN_HISTORY:-20}"
WINDOW="${CC_OUTPUT_SPIKE_WINDOW:-200}"
FLOOR="${CC_OUTPUT_SPIKE_FLOOR:-10000}"
SILENT="${CC_OUTPUT_SPIKE_SILENT:-0}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null

INPUT=$(cat)

# Extract output_tokens from the PostToolUse payload (path varies by tool).
OUT_TOKENS=$(printf '%s' "$INPUT" | jq -r '.tool_response.usage.output_tokens // empty' 2>/dev/null)

# Fallback: read the last assistant turn's usage from the transcript.
if [ -z "$OUT_TOKENS" ]; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
    LAST_USAGE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"usage"' || true)
    if [ -n "$LAST_USAGE" ]; then
      OUT_TOKENS=$(printf '%s' "$LAST_USAGE" | \
        jq -r '.message.usage.output_tokens // .usage.output_tokens // empty' 2>/dev/null)
    fi
  fi
fi

# No usable measurement — exit quietly (this is the common case for many tools).
if [ -z "$OUT_TOKENS" ] || [ "$OUT_TOKENS" = "0" ] || [ "$OUT_TOKENS" = "null" ]; then
  exit 0
fi

# Validate the value is a positive integer.
case "$OUT_TOKENS" in
  ''|*[!0-9]*) exit 0 ;;
esac

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Try to capture the model name too — useful for distinguishing Opus 4.7 vs 4.8 in logs.
MODEL=$(printf '%s' "$INPUT" | jq -r '.tool_response.model // .model // empty' 2>/dev/null)
if [ -z "$MODEL" ] && [ -n "${TRANSCRIPT:-}" ] && [ -r "${TRANSCRIPT:-}" ]; then
  MODEL=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"model"' | jq -r '.message.model // .model // empty' 2>/dev/null || true)
fi
MODEL="${MODEL:-unknown}"

# Append this sample to the rolling log as a JSONL line.
printf '{"ts":"%s","session":"%s","model":"%s","out_tokens":%s}\n' "$TS" "$SESSION_ID" "$MODEL" "$OUT_TOKENS" >> "$LOG"

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
  jq -s 'if length > 0 then (map(.out_tokens) | add / length) else 0 end' 2>/dev/null)

# If the baseline mean is invalid or zero, skip (defensive).
if [ -z "$MEAN" ] || [ "$MEAN" = "0" ] || [ "$MEAN" = "null" ]; then
  exit 0
fi

# Compute ratio = OUT_TOKENS / MEAN. Use awk because bash lacks float arithmetic.
RATIO=$(awk -v c="$OUT_TOKENS" -v m="$MEAN" 'BEGIN { if (m > 0) printf "%.3f", c/m; else print "0" }')
EXCEEDS=$(awk -v r="$RATIO" -v t="$THRESHOLD" 'BEGIN { print (r > t) ? 1 : 0 }')

# Suppress noise: even at threshold ratio, do not alert below the absolute floor.
# A 3× spike from 1k → 3k is normal variance; a 3× spike from 5k → 15k matters.
ABOVE_FLOOR=$(awk -v c="$OUT_TOKENS" -v f="$FLOOR" 'BEGIN { print (c > f) ? 1 : 0 }')

if [ "$EXCEEDS" = "1" ] && [ "$ABOVE_FLOOR" = "1" ] && [ "$SILENT" != "1" ]; then
  # Format the baseline mean as an integer for the human-readable output.
  MEAN_INT=$(awk -v m="$MEAN" 'BEGIN { printf "%d", m }')
  PCT=$(awk -v r="$RATIO" 'BEGIN { printf "%d", (r - 1) * 100 }')
  echo "NOTICE: output_tokens=${OUT_TOKENS} (model=${MODEL}) is ${PCT}% above your trailing-${WINDOW}-sample baseline (~${MEAN_INT})." >&2
  echo "        Possible Cluster 23 candidate signal (Opus 4.8 effort-budget regression, see #64153 / #64152 / #64143)." >&2
  echo "        Mitigations: switch via '/model claude-opus-4-7', set effort=low for routine turns, or audit with:" >&2
  echo "        jq -s 'map(.out_tokens) | sort | .[length/2]' ${LOG}" >&2
fi

exit 0
