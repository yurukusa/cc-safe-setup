#!/bin/bash
# cache-ttl-eviction-detector.sh — alert when long idle gaps cause prompt-cache TTL eviction
#
# Why: Anthropic quietly reduced the prompt-cache TTL from 60 minutes to 5 minutes
#      sometime before 2026-05-30 (community report:
#      https://www.reddit.com/r/ClaudeAI/comments/1tqx8q5/spent_1156308524_input_tokens_in_may_sharing_what/
#      top comment, with 80+ thread responses corroborating).
#      For operators with stable long-running sessions, this can silently 10x
#      effective cost: any idle gap >5 minutes evicts the cache, forcing a fresh
#      cache_creation on the next request that previously would have hit
#      cache_read at ~1/10th the per-token price.
#
#      The existing cache-creation-drift-detector.sh catches per-request
#      inflation but does not correlate to inter-request time gaps. This hook
#      tracks the gap between consecutive PostToolUse events and warns when
#      a >5-minute gap is followed by a request that does NOT achieve the
#      expected cache hit (cache_read_input_tokens below a configurable
#      fraction of total input).
#
# Event: PostToolUse  MATCHER: "" (all tools)
# Action: On each event, read cache_read_input_tokens, cache_creation_input_tokens,
#         and input_tokens from the payload (with transcript fallback). Track the
#         elapsed time since the previous event in a small state file. When the
#         gap exceeds CC_TTL_EVICT_GAP_SECONDS (default 300 = 5 minutes) AND
#         the post-gap event shows a low cache hit ratio
#         (cache_read / (cache_read + cache_creation) < CC_TTL_EVICT_HIT_FLOOR,
#         default 0.50), emit a one-line stderr advisory. Advisory only.
#
# Configuration (all optional):
#   CC_TTL_EVICT_STATE         State file (default: ~/.cache/cc-safe-setup/cache-ttl-state.json)
#   CC_TTL_EVICT_LOG           Event log (default: ~/.cache/cc-safe-setup/cache-ttl-evictions.jsonl)
#   CC_TTL_EVICT_GAP_SECONDS   Idle gap that triggers the check (default: 300 = 5 min)
#   CC_TTL_EVICT_HIT_FLOOR     Minimum cache-hit ratio expected post-gap (default: 0.50)
#   CC_TTL_EVICT_SILENT        Set to "1" to suppress stderr (still logs)
#
# Inspect the log:
#   tail -50 ~/.cache/cc-safe-setup/cache-ttl-evictions.jsonl
#   jq -s 'length' ~/.cache/cc-safe-setup/cache-ttl-evictions.jsonl     # total evictions seen
#
# The registration was missing from this header. The installer reads TRIGGER
# and MATCHER from here and falls back to PreToolUse / Bash when both are
# absent, so this hook was being registered at a moment where the field it
# reads is always empty: it installed, it appeared in the settings, and it
# did nothing. Measured 2026-08-04 across examples/: 14 files were like this.
# TRIGGER: PostToolUse
# MATCHER: ""

set -u

STATE="${CC_TTL_EVICT_STATE:-${HOME}/.cache/cc-safe-setup/cache-ttl-state.json}"
LOG="${CC_TTL_EVICT_LOG:-${HOME}/.cache/cc-safe-setup/cache-ttl-evictions.jsonl}"
GAP_SECONDS="${CC_TTL_EVICT_GAP_SECONDS:-300}"
HIT_FLOOR="${CC_TTL_EVICT_HIT_FLOOR:-0.50}"
SILENT="${CC_TTL_EVICT_SILENT:-0}"

mkdir -p "$(dirname "$STATE")" 2>/dev/null

INPUT=$(cat)

# Helper: extract a numeric usage field from the payload or transcript fallback.
extract_usage() {
  local field="$1"
  local value
  value=$(printf '%s' "$INPUT" | jq -r ".tool_response.usage.${field} // empty" 2>/dev/null)
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    local transcript
    transcript=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    if [ -n "$transcript" ] && [ -r "$transcript" ]; then
      local last_usage
      last_usage=$(tac "$transcript" 2>/dev/null | grep -m1 '"usage"' || true)
      if [ -n "$last_usage" ]; then
        value=$(printf '%s' "$last_usage" | \
          jq -r ".message.usage.${field} // .usage.${field} // empty" 2>/dev/null)
      fi
    fi
  fi
  case "$value" in
    ''|null|*[!0-9]*) echo "0" ;;
    *) echo "$value" ;;
  esac
}

CACHE_READ=$(extract_usage "cache_read_input_tokens")
CACHE_CREATION=$(extract_usage "cache_creation_input_tokens")

# No measurement at all — nothing to track. Exit quietly.
if [ "$CACHE_READ" = "0" ] && [ "$CACHE_CREATION" = "0" ]; then
  exit 0
fi

NOW=$(date -u +%s)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# Load previous state (last event timestamp + session).
PREV_TS=""
PREV_SESSION=""
if [ -r "$STATE" ]; then
  PREV_TS=$(jq -r '.last_event_ts // empty' < "$STATE" 2>/dev/null)
  PREV_SESSION=$(jq -r '.last_session // empty' < "$STATE" 2>/dev/null)
fi

# Write current state immediately so we don't lose it if downstream code errors.
printf '{"last_event_ts":%s,"last_session":"%s"}\n' "$NOW" "$SESSION_ID" > "$STATE"

# Only evaluate gap if we have a previous timestamp AND the session matches.
# Cross-session gaps are not necessarily TTL eviction — session boundary itself
# rebuilds the cache prefix, so we'd produce false positives.
if [ -z "$PREV_TS" ] || [ "$PREV_SESSION" != "$SESSION_ID" ]; then
  exit 0
fi

# Validate prev_ts is an integer (defensive).
case "$PREV_TS" in
  ''|*[!0-9]*) exit 0 ;;
esac

GAP=$((NOW - PREV_TS))

# Gap not long enough to be TTL eviction — exit quietly.
if [ "$GAP" -lt "$GAP_SECONDS" ]; then
  exit 0
fi

# Gap is long enough. Now check the cache hit ratio of this event.
# Ratio = cache_read / (cache_read + cache_creation).
# When TTL has evicted the cache, cache_read goes to ~0 and cache_creation spikes.
HIT_RATIO=$(awk -v r="$CACHE_READ" -v c="$CACHE_CREATION" \
  'BEGIN { tot = r + c; if (tot > 0) printf "%.4f", r/tot; else print "0" }')

# Compare against floor.
EXCEEDS=$(awk -v h="$HIT_RATIO" -v f="$HIT_FLOOR" 'BEGIN { print (h < f) ? 1 : 0 }')

if [ "$EXCEEDS" = "1" ]; then
  # Log the eviction.
  TS_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","session":"%s","gap_seconds":%d,"cache_read":%s,"cache_creation":%s,"hit_ratio":%s}\n' \
    "$TS_ISO" "$SESSION_ID" "$GAP" "$CACHE_READ" "$CACHE_CREATION" "$HIT_RATIO" >> "$LOG"

  if [ "$SILENT" != "1" ]; then
    GAP_MIN=$(awk -v g="$GAP" 'BEGIN { printf "%.1f", g/60 }')
    HIT_PCT=$(awk -v h="$HIT_RATIO" 'BEGIN { printf "%d", h*100 }')
    echo "NOTICE: probable prompt-cache TTL eviction. ${GAP_MIN}-minute idle gap followed by ${HIT_PCT}% cache-hit ratio (floor=${HIT_FLOOR})." >&2
    echo "        Anthropic reduced cache TTL from 60min to 5min (community report 2026-05-30)." >&2
    echo "        Mitigation: avoid >5min idle gaps between requests, or accept the per-eviction recreation cost." >&2
    echo "        Eviction log: ${LOG}" >&2
  fi
fi

exit 0
