#!/bin/bash
# thinking-budget-effort-mismatch-detector.sh — Alert when output_tokens for a
# single turn exceeds the budget that the declared effort tier should imply.
#
# Why: Cluster 23 candidate (Opus 4.8 effort-budget regression) Axis 23B —
#      "effort-tier perception mismatch" — documents that Opus 4.8 under
#      effort=medium can spend 40-50k output tokens on hidden thinking for a
#      routine coding turn, behavior the anchor reporter explicitly states
#      behaves "much closer to a high/xhigh thinking budget" than what the
#      declared effort tier should produce.
#
#      output-token-spike-detector.sh handles Axis 23A (absolute magnitude vs
#      personal baseline). This hook handles Axis 23B (per-tier expected vs
#      observed mismatch) by comparing each turn's output_tokens against the
#      hard per-tier budget the operator has declared via CC_THINKING_EFFORT_TIER.
#
#      Detection rule (defaults, override via env vars):
#        effort=low     → alert above 10,000 output_tokens
#        effort=medium  → alert above 30,000 output_tokens
#        effort=high    → alert above 80,000 output_tokens
#
#      These thresholds come from the Cluster 23 candidate articulation in
#      cluster-tracker.html. low>10k is the "an order of magnitude above
#      routine" floor; medium>30k captures the #64153 anchor magnitude before
#      it reaches the visible 46k figure; high>80k captures the actual
#      xhigh-budget territory that medium tier should not be reaching.
#
#      Together with output-token-spike-detector.sh (rolling-window comparison)
#      and opus48-routine-task-warning.sh (SessionStart up-front articulation),
#      this hook completes the three-hook bundle for Cluster 23 candidate.
#
# Event: PostToolUse  MATCHER: "" (all tools)
# Action: Read output_tokens from the PostToolUse payload (or the last
#         assistant turn in the transcript as fallback). Compare against the
#         tier threshold. Emit a one-line stderr warning if exceeded. Advisory
#         only (exit 0); never blocks.
#
# Configuration (all optional):
#   CC_THINKING_EFFORT_TIER          Declared tier: "low", "medium" (default), "high"
#   CC_THINKING_BUDGET_LOW_MAX       Override low-tier threshold (default: 10000)
#   CC_THINKING_BUDGET_MEDIUM_MAX    Override medium-tier threshold (default: 30000)
#   CC_THINKING_BUDGET_HIGH_MAX      Override high-tier threshold (default: 80000)
#   CC_THINKING_BUDGET_SILENT        Set to "1" to suppress stderr
#   CC_THINKING_BUDGET_DISABLE       Set to "1" to disable entirely
#   CC_THINKING_BUDGET_LOG           Log path (default: ~/.cache/cc-safe-setup/thinking-budget-mismatch.jsonl)

set -u

# Hard disable path
if [ "${CC_THINKING_BUDGET_DISABLE:-0}" = "1" ]; then
  exit 0
fi

TIER="${CC_THINKING_EFFORT_TIER:-medium}"
LOW_MAX="${CC_THINKING_BUDGET_LOW_MAX:-10000}"
MEDIUM_MAX="${CC_THINKING_BUDGET_MEDIUM_MAX:-30000}"
HIGH_MAX="${CC_THINKING_BUDGET_HIGH_MAX:-80000}"
SILENT="${CC_THINKING_BUDGET_SILENT:-0}"
LOG="${CC_THINKING_BUDGET_LOG:-${HOME}/.cache/cc-safe-setup/thinking-budget-mismatch.jsonl}"

# Validate tier; fall back to medium on unrecognized input rather than firing.
case "$TIER" in
  low|medium|high) ;;
  *) TIER="medium" ;;
esac

case "$TIER" in
  low)    THRESHOLD="$LOW_MAX" ;;
  medium) THRESHOLD="$MEDIUM_MAX" ;;
  high)   THRESHOLD="$HIGH_MAX" ;;
esac

# Validate the threshold is a positive integer; defensive fallback.
case "$THRESHOLD" in
  ''|*[!0-9]*) exit 0 ;;
esac

INPUT=$(cat)

OUT_TOKENS=$(printf '%s' "$INPUT" | jq -r '.tool_response.usage.output_tokens // empty' 2>/dev/null)

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

if [ -z "$OUT_TOKENS" ] || [ "$OUT_TOKENS" = "0" ] || [ "$OUT_TOKENS" = "null" ]; then
  exit 0
fi

case "$OUT_TOKENS" in
  ''|*[!0-9]*) exit 0 ;;
esac

# Compare. No alert if within budget.
if [ "$OUT_TOKENS" -le "$THRESHOLD" ]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MODEL=$(printf '%s' "$INPUT" | jq -r '.tool_response.model // .model // empty' 2>/dev/null)
if [ -z "$MODEL" ] && [ -n "${TRANSCRIPT:-}" ] && [ -r "${TRANSCRIPT:-}" ]; then
  MODEL=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"model"' | jq -r '.message.model // .model // empty' 2>/dev/null || true)
fi
MODEL="${MODEL:-unknown}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null
printf '{"ts":"%s","session":"%s","model":"%s","tier":"%s","threshold":%s,"out_tokens":%s}\n' \
  "$TS" "$SESSION_ID" "$MODEL" "$TIER" "$THRESHOLD" "$OUT_TOKENS" >> "$LOG"

if [ "$SILENT" = "1" ]; then
  exit 0
fi

OVERSHOOT=$((OUT_TOKENS - THRESHOLD))

cat >&2 <<EOF
NOTICE: output_tokens=${OUT_TOKENS} exceeded the declared effort tier budget.
        Tier: ${TIER} (threshold ${THRESHOLD}, overshoot ${OVERSHOOT}). Model: ${MODEL}.
        Possible Cluster 23 candidate signal — Axis 23B effort-tier perception
        mismatch (anchor #64153, 5 filings 2026-05-31).
        Mitigations: '/model claude-opus-4-7' (#64153 reporter's comparison
        shows Opus 4.6/4.7 do not exhibit this magnitude), or explicit
        effort=low for routine coding turns to constrain budget regardless of
        whether the calibration regression has been fixed upstream.
        Companion hook: output-token-spike-detector.sh (PostToolUse rolling-
        window comparison surfaces Axis 23A absolute magnitude vs personal
        baseline). Together they cover both effort-mismatch and absolute-
        magnitude signals.
        To suppress: export CC_THINKING_BUDGET_SILENT=1
        Log: ${LOG}
EOF

exit 0
