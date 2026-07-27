#!/bin/bash
# ================================================================
# cron-create-receipt.sh — Log every CronCreate registration
# ================================================================
# PURPOSE:
#   When the model calls CronCreate, write a receipt file so the
#   operator can later audit which cron jobs were registered and
#   compare against actual fire events.
#
# TRIGGER: PostToolUse
# MATCHER: "CronCreate"
#
# WHY THIS MATTERS:
#   CronCreate registration is silent by default — no log entry is
#   produced. When session-scoped cron jobs silently miss fires
#   (issue #62036, #51296, #56108), operators need the registration
#   list to compare against actual fire timestamps. Without this
#   receipt, the registration side of the audit is invisible.
#
#   Pair with the prompt-side receipt pattern (touch on each fire)
#   to produce a full audit:
#     Registration count (this hook) vs fire count (touch receipts)
#
# WHAT IT WRITES:
#   ~/.claude/state/crons/registered/<timestamp>-<seq>.json
#   Each receipt contains:
#     - registered_at: ISO 8601 timestamp
#     - cron_expression: the cron spec (e.g. "40 * * * *")
#     - recurring: boolean
#     - prompt_excerpt: first 200 chars of the prompt (truncated)
#     - tool_output_excerpt: first 200 chars of the response
#
# DEFENSIVE BEHAVIOR:
#   - Always exits 0 (advisory only, never blocks)
#   - Skips silently if state directory cannot be created
#   - Skips silently if jq is missing
#   - Truncates prompt to 200 chars to keep receipt file size bounded
#
# CONFIGURATION (environment variables):
#   CC_CRON_RECEIPT_DISABLE=1   skip the hook entirely
#   CC_CRON_RECEIPT_DIR=...     override the state directory
#   CC_CRON_RECEIPT_EXCERPT_LEN truncation length (default 200)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/62036  (ulogan, 2026-05-24)
#   https://github.com/anthropics/claude-code/issues/56108  (one-shot queue)
#   https://github.com/anthropics/claude-code/issues/51296  (never fires)
#
# RELATED PUBLIC RESOURCES:
#   https://gist.github.com/yurukusa/a56f858169688b264510ed1c07181e65  (structural analysis)
#   https://gist.github.com/yurukusa/42b6da4c53a836ac3aa809f463da45be  (scheduled-routine-watchdog.sh)
# ================================================================

set -u

# Skip if disabled
if [ "${CC_CRON_RECEIPT_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Skip if jq is missing — we cannot parse tool_input without it
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat)

STATE_DIR="${CC_CRON_RECEIPT_DIR:-$HOME/.claude/state/crons/registered}"
EXCERPT_LEN="${CC_CRON_RECEIPT_EXCERPT_LEN:-200}"

# Create state directory; skip silently on failure (read-only fs, etc.)
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Extract fields defensively
CRON_EXPR=$(printf '%s' "$INPUT" | jq -r '.tool_input.cron // empty' 2>/dev/null)

# Skip if no cron expression — the hook only fires on CronCreate but
# defensive check guards against malformed input
if [ -z "$CRON_EXPR" ]; then
  exit 0
fi

RECURRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.recurring // false' 2>/dev/null)
PROMPT_RAW=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
RESULT_RAW=$(printf '%s' "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null)

# Truncate to bounded length
PROMPT_EXCERPT=$(printf '%s' "$PROMPT_RAW" | head -c "$EXCERPT_LEN")
RESULT_EXCERPT=$(printf '%s' "$RESULT_RAW" | head -c "$EXCERPT_LEN")

# Generate unique receipt filename: timestamp + 4-char random suffix
TS=$(date -u '+%Y%m%dT%H%M%SZ')
SEQ=$(printf '%04x' "$RANDOM" 2>/dev/null || echo "0000")
RECEIPT_FILE="$STATE_DIR/$TS-$SEQ.json"

# Compose receipt JSON via jq for safe quoting
jq -n \
  --arg registered_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg cron_expression "$CRON_EXPR" \
  --argjson recurring "$RECURRING" \
  --arg prompt_excerpt "$PROMPT_EXCERPT" \
  --arg tool_output_excerpt "$RESULT_EXCERPT" \
  '{
    registered_at: $registered_at,
    cron_expression: $cron_expression,
    recurring: $recurring,
    prompt_excerpt: $prompt_excerpt,
    tool_output_excerpt: $tool_output_excerpt
  }' > "$RECEIPT_FILE" 2>/dev/null || exit 0

# Always exit 0 — advisory only, never blocks CronCreate
exit 0
