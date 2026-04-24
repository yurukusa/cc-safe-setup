#!/bin/bash
# cache-tier-logger.sh — cache TTL regression detector (Incident 1)
# Why: March 2026 regression silently downgraded the prompt-cache TTL from 1h to
#      5m (ephemeral_5m), causing cache re-creation every turn. Users saw quota
#      burn at 4-5x without any client-side change. Issue #46829 (119,866-call
#      dataset), #46917 (cache_creation inflation).
# Event: PostToolUse  MATCHER: "*"
# Action: Per tool call, inspect the PostToolUse payload for cache usage fields
#         and append a TSV line to ~/.claude/logs/cache-tier.log.
#
# Review weekly with:
#   awk -F'\t' '{print $4}' ~/.claude/logs/cache-tier.log | sort | uniq -c
# Main-conversation turns should skew toward large cache_read_input_tokens
# relative to cache_creation_input_tokens. A session where cache_creation
# dominates every turn is the silent-downgrade signal.

set -u

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/cache-tier.log"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
CACHE_READ=$(printf '%s' "$INPUT" | jq -r '.tool_response.usage.cache_read_input_tokens // empty' 2>/dev/null)
CACHE_CREATE=$(printf '%s' "$INPUT" | jq -r '.tool_response.usage.cache_creation_input_tokens // empty' 2>/dev/null)

# Fallback: when PostToolUse payload has no usage (most tools), read the last
# assistant turn from the transcript. This is cheap — one tac|head|jq.
if [ -z "$CACHE_READ" ] && [ -z "$CACHE_CREATE" ]; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
    LAST_USAGE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"usage"' || true)
    if [ -n "$LAST_USAGE" ]; then
      CACHE_READ=$(printf '%s' "$LAST_USAGE" | jq -r '.message.usage.cache_read_input_tokens // .usage.cache_read_input_tokens // empty' 2>/dev/null)
      CACHE_CREATE=$(printf '%s' "$LAST_USAGE" | jq -r '.message.usage.cache_creation_input_tokens // .usage.cache_creation_input_tokens // empty' 2>/dev/null)
    fi
  fi
fi

CACHE_READ="${CACHE_READ:-0}"
CACHE_CREATE="${CACHE_CREATE:-0}"

# Infer tier: if a turn had cache reads, the prefix was still valid (tier hit).
# If only creations, the previous prefix expired — this is the signal that
# matters for TTL regression. ephemeral_5m burns creations every turn.
if [ "$CACHE_READ" -gt 0 ] 2>/dev/null; then
  TIER="cache_hit"
elif [ "$CACHE_CREATE" -gt 0 ] 2>/dev/null; then
  TIER="cache_miss"
else
  TIER="no_cache_data"
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$TS" "$SESSION_ID" "$TOOL_NAME" "$TIER" "$CACHE_READ" "$CACHE_CREATE" \
  >> "$LOG_FILE"

exit 0
