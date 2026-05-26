#!/bin/bash
# session-rate-monitor.sh — alert when a single session's token burn rate exceeds an absolute ceiling
#
# Why: The Pro Max quota anomaly cluster (#16157 / #38335 / #45756 / #41788 /
#      #29579 / #19673) repeatedly reports the same scenario: a session that
#      hits the usage limit within minutes of starting, before the operator
#      has any chance to see a per-request drift signal or a cross-session
#      rolling-baseline divergence. The two earlier hooks in this family
#      need historical samples before they can speak:
#
#        - cache-creation-drift-detector.sh needs a 200-sample trailing window
#          and only triggers on per-request server-side inflation (#46917).
#        - quota-anomaly-detector.sh needs 30+ samples and a 24-hour baseline
#          before it has a personal rate to compare against.
#
#      Neither catches a brand-new session that burns 100K tokens in the
#      first five minutes. This hook closes that gap by tracking per-session
#      elapsed-time and cumulative tokens, then alerting against an absolute
#      tokens-per-minute ceiling. No baseline required; works from request 1.
#
#      Composes with cache-creation-drift-detector (per-request) and
#      quota-anomaly-detector (cross-session). Three orthogonal signals,
#      three latencies: per-request → per-session → cross-session.
#
# Event: PostToolUse  MATCHER: "" (all tools)
# Action: Sum input + output + cache_read + cache_creation tokens from each
#         PostToolUse payload. Maintain per-session state in a small file
#         keyed by session_id, accumulating start_epoch, total_tokens, and
#         sample_count. Compute current rate = total_tokens / minutes_elapsed
#         and emit a one-line stderr warning when it exceeds an absolute
#         threshold (default 50,000 tok/min). Re-alerts at most once every
#         N minutes to avoid spam. Advisory only (exit 0); does not block.
#
# Configuration (all optional):
#   CC_SESSION_RATE_DIR          State dir (default: ~/.cache/cc-safe-setup/session-rate)
#   CC_SESSION_RATE_THRESHOLD    Alert ceiling in tokens/minute (default: 50000)
#   CC_SESSION_RATE_MIN_SAMPLES  Minimum samples before alerting (default: 5)
#   CC_SESSION_RATE_MIN_ELAPSED  Minimum session-elapsed seconds before alerting (default: 60)
#   CC_SESSION_RATE_REPEAT_MIN   Suppress repeat alerts for N minutes (default: 5)
#   CC_SESSION_RATE_SILENT       Set to "1" to suppress stderr (still tracks)
#
# Inspect state:
#   ls -la ~/.cache/cc-safe-setup/session-rate/
#   cat ~/.cache/cc-safe-setup/session-rate/<session_id>

set -u

STATE_DIR="${CC_SESSION_RATE_DIR:-${HOME}/.cache/cc-safe-setup/session-rate}"
THRESHOLD="${CC_SESSION_RATE_THRESHOLD:-50000}"
MIN_SAMPLES="${CC_SESSION_RATE_MIN_SAMPLES:-5}"
MIN_ELAPSED="${CC_SESSION_RATE_MIN_ELAPSED:-60}"
REPEAT_MIN="${CC_SESSION_RATE_REPEAT_MIN:-5}"
SILENT="${CC_SESSION_RATE_SILENT:-0}"

mkdir -p "$STATE_DIR" 2>/dev/null

INPUT=$(cat)

# Extract session_id; if missing, we can't track per-session state.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
  exit 0
fi

# Sanitize session_id for use as a filename (allow alnum, dash, underscore).
SAFE_ID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-128)
STATE_FILE="$STATE_DIR/$SAFE_ID"

# Sum the four token fields from PostToolUse payload.
TOTAL=$(printf '%s' "$INPUT" | jq -r '
  def num(x): if (x | type) == "number" then x else 0 end;
  (.tool_response.usage // null) as $u |
  if $u == null then empty
  else
    (num($u.input_tokens) + num($u.output_tokens) +
     num($u.cache_read_input_tokens) + num($u.cache_creation_input_tokens))
  end
' 2>/dev/null)

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

if [ -z "$TOTAL" ] || [ "$TOTAL" = "0" ] || [ "$TOTAL" = "null" ]; then
  exit 0
fi

case "$TOTAL" in
  ''|*[!0-9]*) exit 0 ;;
esac

NOW_EPOCH=$(date -u +%s)

# Read existing state or initialize. State format (single line, space-separated):
#   start_epoch total_tokens sample_count last_alert_epoch
if [ -f "$STATE_FILE" ]; then
  read -r START_EPOCH OLD_TOTAL OLD_COUNT LAST_ALERT < "$STATE_FILE" 2>/dev/null
  START_EPOCH="${START_EPOCH:-$NOW_EPOCH}"
  OLD_TOTAL="${OLD_TOTAL:-0}"
  OLD_COUNT="${OLD_COUNT:-0}"
  LAST_ALERT="${LAST_ALERT:-0}"
else
  START_EPOCH="$NOW_EPOCH"
  OLD_TOTAL=0
  OLD_COUNT=0
  LAST_ALERT=0
fi

NEW_TOTAL=$((OLD_TOTAL + TOTAL))
NEW_COUNT=$((OLD_COUNT + 1))
ELAPSED=$((NOW_EPOCH - START_EPOCH))

# Write updated state (preserve LAST_ALERT for now; updated below on alert).
printf '%s %s %s %s\n' "$START_EPOCH" "$NEW_TOTAL" "$NEW_COUNT" "$LAST_ALERT" > "$STATE_FILE"

# Need enough samples and enough elapsed time before computing a rate.
if [ "$NEW_COUNT" -lt "$MIN_SAMPLES" ]; then
  exit 0
fi
if [ "$ELAPSED" -lt "$MIN_ELAPSED" ]; then
  exit 0
fi

# Compute rate in tokens/minute. Use awk for float division.
RATE=$(awk -v t="$NEW_TOTAL" -v e="$ELAPSED" 'BEGIN { if (e > 0) printf "%.0f", t * 60 / e; else print "0" }')

# Compare against threshold.
EXCEEDS=$(awk -v r="$RATE" -v th="$THRESHOLD" 'BEGIN { print (r > th) ? 1 : 0 }')
if [ "$EXCEEDS" != "1" ]; then
  exit 0
fi

# Repeat-alert suppression: only re-alert every REPEAT_MIN minutes.
SINCE_LAST=$((NOW_EPOCH - LAST_ALERT))
REPEAT_SEC=$((REPEAT_MIN * 60))
if [ "$LAST_ALERT" != "0" ] && [ "$SINCE_LAST" -lt "$REPEAT_SEC" ]; then
  exit 0
fi

# Record this alert time.
printf '%s %s %s %s\n' "$START_EPOCH" "$NEW_TOTAL" "$NEW_COUNT" "$NOW_EPOCH" > "$STATE_FILE"

if [ "$SILENT" = "1" ]; then
  exit 0
fi

ELAPSED_MIN=$(awk -v e="$ELAPSED" 'BEGIN { printf "%.1f", e / 60 }')
echo "NOTICE: session burning ~${RATE} tok/min over the first ${ELAPSED_MIN}min (${NEW_TOTAL} tokens, ${NEW_COUNT} requests)." >&2
echo "        This exceeds the ${THRESHOLD} tok/min ceiling — at this rate a Max-5x daily quota empties fast." >&2
echo "        Pro Max quota anomaly cluster: anthropics/claude-code #16157 / #38335 / #45756 / #41788." >&2
echo "        Adjust ceiling with CC_SESSION_RATE_THRESHOLD or silence with CC_SESSION_RATE_SILENT=1." >&2

exit 0
