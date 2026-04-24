#!/bin/bash
# context-length-budget.sh — long-context retrieval regression guard (Incident 6)
# Why: Opus 4.7 shows significant retrieval accuracy regressions above 200K
#      tokens of context (MRCR -46pt, 256k-8-needle -32.7pt). This hook
#      tracks cumulative input-token usage across a session and emits an
#      advisory when the budget threshold is crossed, so you can split the
#      workflow before results start degrading.
# Event: PreToolUse  MATCHER: "*"
# Action: Read the latest usage total from the transcript, append to the
#         session's context-budget log, and warn once per session when the
#         cumulative input tokens cross the budget line.
#
# Environment:
#   CONTEXT_BUDGET_THRESHOLD    tokens above which to warn (default 200000)
#
# The threshold is advisory, not absolute. Sessions can run above 200K and
# perform fine if retrieval is not multi-round. Treat the alert as a reason
# to verify accuracy, not a reason to abort.

set -u

THRESHOLD="${CONTEXT_BUDGET_THRESHOLD:-200000}"
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
[ "$SESSION_ID" = "unknown" ] && exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Read the most recent usage record and compute cumulative input = input +
# cache_read + cache_creation. cache_read counts against the context window
# even when it did not cost extra tokens, because retrieval happens over the
# reconstructed context.
LAST_USAGE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"usage"' || true)
[ -z "$LAST_USAGE" ] && exit 0

INPUT_TOK=$(printf '%s' "$LAST_USAGE" | jq -r '.message.usage.input_tokens // .usage.input_tokens // 0' 2>/dev/null)
CACHE_READ=$(printf '%s' "$LAST_USAGE" | jq -r '.message.usage.cache_read_input_tokens // .usage.cache_read_input_tokens // 0' 2>/dev/null)
CACHE_CREATE=$(printf '%s' "$LAST_USAGE" | jq -r '.message.usage.cache_creation_input_tokens // .usage.cache_creation_input_tokens // 0' 2>/dev/null)

INPUT_TOK=${INPUT_TOK:-0}
CACHE_READ=${CACHE_READ:-0}
CACHE_CREATE=${CACHE_CREATE:-0}

CUMULATIVE=$((INPUT_TOK + CACHE_READ + CACHE_CREATE))

LOG_FILE="${LOG_DIR}/context-budget-${SESSION_ID}.log"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\t%s\t%s\t%s\t%s\n' "$TS" "$CUMULATIVE" "$INPUT_TOK" "$CACHE_READ" "$CACHE_CREATE" >> "$LOG_FILE"

# Warn once per session when the threshold is first crossed. Track with a
# sentinel file so we do not re-warn on every subsequent turn.
SENTINEL="${LOG_DIR}/context-budget-${SESSION_ID}.warned"
if [ "$CUMULATIVE" -gt "$THRESHOLD" ] && [ ! -f "$SENTINEL" ]; then
  echo "⚠ context-length-budget: $CUMULATIVE tokens in session context (threshold ${THRESHOLD})" >&2
  echo "  Opus 4.7 shows retrieval accuracy drops above 200K (MRCR -46pt). Consider splitting the workflow or running /compact." >&2
  touch "$SENTINEL"
fi

exit 0
