#!/bin/bash
# model-swap-suggester.sh — Evidence-driven swap recommendation for the AUP false-positive cluster
#
# Background:
#   Cluster 9 (Usage Policy classifier over-trigger) accumulated 25+ open GitHub issues
#   between 2026-05-18 and 2026-05-27, with Opus 4.7 / 4.6 / 1M variants over-triggering
#   on benign Claude Code prompts (English, Russian, Polish, Spanish; kernel security,
#   biomedical, FPGA, plain greetings — context-independent). Sonnet variants are reported
#   unaffected.
#
#   Two defense hooks ship today:
#     - aup-false-positive-helper.sh   (SessionStart, opt-in, generic awareness)
#     - aup-block-pattern-logger.sh    (PostToolUse, on-by-default, records each block)
#
#   The gap they leave: the operator who is actively being blocked needs an evidence-driven
#   recommendation at the right moment — "you have been blocked N times in the last hour
#   on Opus, here is the exact swap command." The helper hook is generic and fires on every
#   Opus session; the logger collects evidence but does not act on it.
#
#   This hook closes that loop. On SessionStart, it reads the block log written by the
#   logger, counts Opus blocks in a recent time window, and emits a concrete swap-to-Sonnet
#   advisory only when the count crosses a threshold. Silent otherwise.
#
#   Reference: https://gist.github.com/yurukusa/4fa4751044be45bd83345601ee79c2db
#
# What this hook does:
#   On SessionStart, if ANTHROPIC_MODEL is pinned to an Opus variant AND the AUP block log
#   shows N or more blocks on any Opus model in the last M minutes, emit a one-time advisory
#   with the exact swap command for the current session. Silent in every other case.
#
# When this hook does NOT emit anything:
#   - CC_MODEL_SWAP_SUGGESTER_DISABLE=1
#   - CC_MODEL_SWAP_SUGGESTER_QUIET=1
#   - ANTHROPIC_MODEL unset                                  (default routing)
#   - ANTHROPIC_MODEL pinned to a non-Opus variant           (Sonnet / Haiku unaffected)
#   - aup-block log missing, empty, or unreadable
#   - Opus blocks in the configured window < threshold
#
# Hook config (settings.json):
# {
#   "hooks": {
#     "SessionStart": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/model-swap-suggester.sh" }]
#     }]
#   }
# }
#
# Env vars:
#   CC_MODEL_SWAP_SUGGESTER_DISABLE=1        — never emit
#   CC_MODEL_SWAP_SUGGESTER_QUIET=1          — silent (post-acknowledgment)
#   CC_MODEL_SWAP_SUGGESTER_THRESHOLD=<n>    — Opus block count threshold (default 3)
#   CC_MODEL_SWAP_SUGGESTER_WINDOW_MIN=<n>   — lookback window in minutes (default 60)
#   CC_MODEL_SWAP_SUGGESTER_TARGET=<model>   — target Sonnet model (default claude-sonnet-4-7)
#   CC_AUP_BLOCK_LOG_PATH=<path>             — log path (shared with logger; default ~/.claude/aup-block-history.log)
#
# Design notes:
#   - Evidence-driven, not opt-in. The advisory only fires when real blocks have happened,
#     so it never adds noise for users who haven't been affected.
#   - Counts Opus blocks across all Opus variants in the log (not just the currently pinned
#     model), because the cluster signature is Opus-family-wide. If you swapped from
#     opus-4-7 to opus-4-6 mid-day and both blocked, both count toward the threshold.
#   - Window is timestamp-based, not last-N-lines, so a quiet session with stale entries
#     does not trigger the advisory.
#   - Never blocks. All failure paths exit 0 so a corrupt log or missing date utility
#     cannot break the session.

set -u

# Disable path
if [ "${CC_MODEL_SWAP_SUGGESTER_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Quiet path
if [ "${CC_MODEL_SWAP_SUGGESTER_QUIET:-0}" = "1" ]; then
  exit 0
fi

# Model unset → default routing, no specific advisory
if [ -z "${ANTHROPIC_MODEL:-}" ]; then
  exit 0
fi

# Non-Opus model → unaffected by the cluster
case "$ANTHROPIC_MODEL" in
  *opus*|*Opus*|*OPUS*) : ;;
  *) exit 0 ;;
esac

LOG_PATH="${CC_AUP_BLOCK_LOG_PATH:-$HOME/.claude/aup-block-history.log}"
[ -f "$LOG_PATH" ] || exit 0
[ -r "$LOG_PATH" ] || exit 0
[ -s "$LOG_PATH" ] || exit 0

THRESHOLD="${CC_MODEL_SWAP_SUGGESTER_THRESHOLD:-3}"
WINDOW_MIN="${CC_MODEL_SWAP_SUGGESTER_WINDOW_MIN:-60}"
TARGET="${CC_MODEL_SWAP_SUGGESTER_TARGET:-claude-sonnet-4-7}"

# Validate numeric env vars; fall back to defaults on garbage input.
case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD=3 ;;
esac
case "$WINDOW_MIN" in
  ''|*[!0-9]*) WINDOW_MIN=60 ;;
esac

# Compute cutoff epoch (now - window_min * 60). Use GNU date first, then BSD date.
NOW=$(date -u '+%s' 2>/dev/null) || exit 0
CUTOFF=$((NOW - WINDOW_MIN * 60))

ts_to_epoch() {
  local ts="$1"
  date -u -d "$ts" '+%s' 2>/dev/null \
    || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%s' 2>/dev/null
}

# Count Opus blocks in the window. The log schema is:
#   ISO8601_UTC | MODEL | TOOL | PATTERN_KIND | EXCERPT
# We only count rows whose model field matches an Opus variant and whose timestamp falls
# inside the cutoff window. Rows with unparseable timestamps are skipped silently.
COUNT=0
while IFS='|' read -r LOG_TS LOG_MODEL _LOG_TOOL _LOG_KIND _LOG_EXCERPT; do
  [ -z "$LOG_TS" ] && continue
  [ -z "$LOG_MODEL" ] && continue
  case "$LOG_MODEL" in
    *opus*|*Opus*|*OPUS*) : ;;
    *) continue ;;
  esac
  LOG_EPOCH=$(ts_to_epoch "$LOG_TS")
  [ -z "$LOG_EPOCH" ] && continue
  case "$LOG_EPOCH" in
    *[!0-9]*) continue ;;
  esac
  if [ "$LOG_EPOCH" -ge "$CUTOFF" ] 2>/dev/null; then
    COUNT=$((COUNT + 1))
  fi
done < "$LOG_PATH"

if [ "$COUNT" -lt "$THRESHOLD" ] 2>/dev/null; then
  exit 0
fi

# Threshold crossed → emit one-time advisory. The advisory is deliberately concrete:
# exact swap command, exact env-var suppression command, and pointers to the partner hooks
# the operator can lean on after swapping.
cat >&2 <<EOF
[model-swap-suggester] $COUNT Usage Policy block(s) recorded on Opus models in the last $WINDOW_MIN minutes.

Current model: $ANTHROPIC_MODEL
Log file:      $LOG_PATH

The Anthropic Usage Policy classifier has been over-triggering on benign prompts on Opus
variants since 2026-05-18. Sonnet variants are reportedly unaffected. Recommended swap
for this session:

  export ANTHROPIC_MODEL=$TARGET

After swapping, the false-positive helper will go silent automatically (Sonnet is treated
as unaffected). Re-pin Opus once the upstream classifier stabilises.

Related hooks (already shipped):
  aup-false-positive-helper.sh — generic awareness advisory (opt-in via CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1)
  aup-block-pattern-logger.sh  — records each block to $LOG_PATH

To silence this advisory permanently for the current session, even when blocks continue:
  export CC_MODEL_SWAP_SUGGESTER_QUIET=1

To raise the threshold instead of silencing:
  export CC_MODEL_SWAP_SUGGESTER_THRESHOLD=10   # only suggest after 10 blocks in $WINDOW_MIN min

GitHub tracker (25+ independent reports, 2026-05-18 through 2026-05-27):
  https://github.com/anthropics/claude-code/issues/60366
  https://github.com/anthropics/claude-code/issues/62190
EOF

exit 0
