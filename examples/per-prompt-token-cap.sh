#!/bin/bash
# ================================================================
# per-prompt-token-cap.sh — Detect single-prompt quota burnout
# ================================================================
# PURPOSE:
#   Detect when a single user prompt is consuming an outsized
#   fraction of the 5-hour quota. The May 2026 cluster around
#   Issue #56297 documented eight reports where one prompt drove
#   the 5-hour quota to 100% before any output was produced.
#   The pattern is invisible to session-cumulative budget guards
#   (token-budget-guard, daily-cost-guard) and to rapid-tool-call
#   detectors (token-spike-alert) because the prompt may make
#   only a handful of tool calls while consuming millions of
#   input tokens via re-reads, sub-agent invocations, or long
#   thinking chains.
#
#   This hook reads the session transcript for the boundary of
#   the most recent user prompt and sums the input_tokens across
#   the assistant turns that have followed. If the sum exceeds
#   PER_PROMPT_TOKEN_CAP, the hook emits a warning to stderr.
#
# TRIGGER: PostToolUse  MATCHER: ""
#
# CONFIG:
#   PER_PROMPT_TOKEN_CAP=1000000   (warn at 1M input tokens)
#   PER_PROMPT_TOKEN_BLOCK=0       (0 = warn-only; set positive to block)
#
# Born from: https://github.com/anthropics/claude-code/issues/56297
#   plus #56276 #56293 #56292 #56265 #56259 #56252 #56239
#   (May 5 2026 cluster — 8 issues filed in a 6-hour window)
# ================================================================

set -euo pipefail

WARN_CAP="${PER_PROMPT_TOKEN_CAP:-1000000}"
BLOCK_CAP="${PER_PROMPT_TOKEN_BLOCK:-0}"

# Read JSON input from stdin (hook input format)
INPUT=$(cat)

# Extract transcript_path from the hook input
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# If no transcript path, exit silently (no measurement possible)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# Walk the transcript backward to find the boundary of the latest user prompt.
# The transcript is JSONL where each line is one turn. We sum input_tokens
# from assistant turns occurring after the most recent user turn.
#
# tac reverses lines so we encounter the latest entries first; we accumulate
# input_tokens from assistant lines and stop when we hit a user line.
#
# Schema reference: each line has .type ("user"|"assistant"|"system"|...)
# and assistant lines have .message.usage.input_tokens (cache_creation +
# cache_read + raw input). We sum the total input load.

CURRENT_PROMPT_TOKENS=$(tac "$TRANSCRIPT" 2>/dev/null | awk '
  BEGIN { sum = 0 }
  {
    # Stop when we encounter the most recent user turn
    if ($0 ~ /"type"[[:space:]]*:[[:space:]]*"user"/) { exit }
    # Sum input_tokens from assistant turns after the latest user turn
    if ($0 ~ /"type"[[:space:]]*:[[:space:]]*"assistant"/) {
      # Extract input_tokens, cache_creation_input_tokens, cache_read_input_tokens
      n = match($0, /"input_tokens"[[:space:]]*:[[:space:]]*[0-9]+/)
      if (n > 0) {
        s = substr($0, n)
        match(s, /[0-9]+/)
        sum += substr(s, RSTART, RLENGTH) + 0
      }
      n = match($0, /"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]+/)
      if (n > 0) {
        s = substr($0, n)
        match(s, /[0-9]+/)
        sum += substr(s, RSTART, RLENGTH) + 0
      }
      n = match($0, /"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]+/)
      if (n > 0) {
        s = substr($0, n)
        match(s, /[0-9]+/)
        sum += substr(s, RSTART, RLENGTH) + 0
      }
    }
  }
  END { print sum }
')

# If awk produced an empty or invalid value, treat as zero
[ -z "$CURRENT_PROMPT_TOKENS" ] && CURRENT_PROMPT_TOKENS=0
case "$CURRENT_PROMPT_TOKENS" in
  *[!0-9]*) CURRENT_PROMPT_TOKENS=0 ;;
esac

# Block path: if BLOCK_CAP set and exceeded, emit blocking message and exit 2
if [ "$BLOCK_CAP" -gt 0 ] && [ "$CURRENT_PROMPT_TOKENS" -gt "$BLOCK_CAP" ]; then
  echo "BLOCKED: per-prompt-token-cap: this prompt consumed ${CURRENT_PROMPT_TOKENS} input tokens, exceeding the block cap of ${BLOCK_CAP}." >&2
  echo "  Pattern matches the May 2026 #56297 cluster (single prompt burns 5-hour quota before output)." >&2
  echo "  To proceed: end the current session with /clear and start a fresh prompt with narrower scope." >&2
  echo "  To raise the cap: export PER_PROMPT_TOKEN_BLOCK=<higher value>." >&2
  exit 2
fi

# Warn path: if cap exceeded, emit a non-blocking warning
if [ "$CURRENT_PROMPT_TOKENS" -gt "$WARN_CAP" ]; then
  echo "WARNING: per-prompt-token-cap: this prompt has consumed ${CURRENT_PROMPT_TOKENS} input tokens, exceeding the warn cap of ${WARN_CAP}." >&2
  echo "  This is the May 2026 #56297 cluster pattern (single prompt burns quota before output)." >&2
  echo "  Consider /clear and restart with a narrower scope. Run /usage --json to confirm 5-hour quota state." >&2
fi

exit 0
