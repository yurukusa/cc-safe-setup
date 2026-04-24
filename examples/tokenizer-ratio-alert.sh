#!/bin/bash
# tokenizer-ratio-alert.sh — Opus 4.7 tokenizer inflation monitor (Incident 5)
# Why: Opus 4.7 encodes the same prompt 1.35-1.46x larger than Opus 4.6
#      (Anthropic stated ceiling 1.35, Simon Willison independent verification
#      1.46 for system prompts). If you have pinned 4.6 but want to verify
#      token accounting is actually on 4.6, this hook measures the ratio by
#      calling the count_tokens endpoint against both models and alerts when
#      the observed ratio exceeds a threshold.
# Event: PreToolUse  MATCHER: "*"   (filter inside for model-bound turns)
# Action: When the incoming tool call is a large enough user turn,
#         compute count_tokens(4.6) and count_tokens(4.7) via the Anthropic
#         API and emit a stderr alert if ratio > TOKENIZER_RATIO_THRESHOLD.
#
# Runtime cost: two network calls per eligible turn (tens to hundreds of ms).
# This is the most expensive hook in the catalog. Enable only while actively
# investigating an incident, then disable.
#
# Environment:
#   ANTHROPIC_API_KEY              required for real count_tokens calls
#   TOKENIZER_RATIO_THRESHOLD      ratio above which to alert (default 1.40)
#   TOKENIZER_MIN_PROMPT_TOKENS    skip measurement for prompts below this
#                                   many characters / 4 ≈ tokens (default 500)
#   TOKENIZER_RATIO_ENDPOINT       override API base URL (for tests)
#   TOKENIZER_RATIO_MODEL_OLD      (default claude-opus-4-6)
#   TOKENIZER_RATIO_MODEL_NEW      (default claude-opus-4-7)

set -u

THRESHOLD="${TOKENIZER_RATIO_THRESHOLD:-1.40}"
MIN_CHARS="${TOKENIZER_MIN_PROMPT_TOKENS:-500}"   # used as char cutoff, not true tokens
MIN_CHARS=$((MIN_CHARS * 4))                      # 1 token ≈ 4 chars for quick filter
ENDPOINT="${TOKENIZER_RATIO_ENDPOINT:-https://api.anthropic.com}"
MODEL_OLD="${TOKENIZER_RATIO_MODEL_OLD:-claude-opus-4-6}"
MODEL_NEW="${TOKENIZER_RATIO_MODEL_NEW:-claude-opus-4-7}"

INPUT=$(cat)

# Extract prompt text. For a conversation-bound tool invocation, the most
# recent user turn's text is a reasonable proxy for "what the model just
# paid to encode."
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
PROMPT=""
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  PROMPT=$(tac "$TRANSCRIPT" 2>/dev/null \
           | grep -m1 '"role":"user"' \
           | jq -r '.message.content[0].text // .message.content // .content // empty' 2>/dev/null)
fi

# Fallback to direct prompt-like field on the payload (for tests and
# unusual tools that carry the turn text inline).
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // .tool_input.text // empty' 2>/dev/null)
fi

[ -z "$PROMPT" ] && exit 0

LEN=${#PROMPT}
if [ "$LEN" -lt "$MIN_CHARS" ]; then
  exit 0
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "tokenizer-ratio-alert: ANTHROPIC_API_KEY not set, skipping (hook is a no-op)" >&2
  exit 0
fi

count_tokens() {
  local model="$1"
  local body
  body=$(jq -n --arg model "$model" --arg text "$PROMPT" \
    '{model: $model, messages: [{role: "user", content: $text}]}')
  curl -s --max-time 10 -X POST "$ENDPOINT/v1/messages/count_tokens" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$body" 2>/dev/null \
    | jq -r '.input_tokens // empty' 2>/dev/null
}

OLD=$(count_tokens "$MODEL_OLD")
NEW=$(count_tokens "$MODEL_NEW")

if [ -z "$OLD" ] || [ -z "$NEW" ] || [ "$OLD" -eq 0 ] 2>/dev/null; then
  exit 0
fi

# Compute ratio as floating-point via awk (no bc dependency).
RATIO=$(awk -v n="$NEW" -v o="$OLD" 'BEGIN { if (o > 0) printf "%.4f", n/o; else print "0" }')
EXCEEDS=$(awk -v r="$RATIO" -v t="$THRESHOLD" 'BEGIN { print (r > t) ? 1 : 0 }')

if [ "$EXCEEDS" = "1" ]; then
  echo "⚠ tokenizer-ratio-alert: $MODEL_NEW=$NEW tokens vs $MODEL_OLD=$OLD tokens (ratio ${RATIO}, threshold ${THRESHOLD})" >&2
  echo "  Opus 4.7 tokenizer encodes this prompt larger than 4.6 by more than the expected 1.35x ceiling." >&2
fi

exit 0
