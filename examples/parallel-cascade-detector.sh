#!/bin/bash
# ================================================================
# parallel-cascade-detector.sh — Detect parallel-batch cascade
# ================================================================
# PURPOSE:
#   When Claude Code sends parallel tool calls in a single assistant
#   turn and one of them errors, all sibling calls are cancelled with
#   "Cancelled: parallel tool call X errored" — even when the failure
#   is non-fatal (exit 144 from pkill, expected 404 from curl,
#   invalid git revision, etc.).
#
#   Two problems:
#   1. The whole batch's compute is wasted (40-100K tokens / cascade).
#   2. The cancellation message is indistinguishable from a user
#      interrupt, so the model itself can misattribute the cascade
#      to user action and fabricate user statements ("You're right
#      to stop me…") — see Issue #64047.
#
#   This hook counts cascade events in a rolling time window and
#   warns when the count crosses a configurable threshold. It does
#   NOT prevent cascades (the policy is upstream) — it surfaces them
#   so operators can recognize the pattern and restructure batches.
#
# CLUSTER:
#   Candidate cluster #20 — parallel tool batch cancellation cascade
#   3 independent reports on 2026-05-30:
#   - #64059 (enrico2468) - confirmed behavior across long sessions
#   - #64052 (omar16100) - minimal reproduction on v2.1.158
#   - #64047 (snichols) - the indistinguishability + fabrication
#
# TRIGGER: PostToolUse  MATCHER: ""
#
# ENV:
#   CC_PARALLEL_CASCADE_THRESHOLD   default 5
#   CC_PARALLEL_CASCADE_WINDOW_SEC  default 60
#   CC_PARALLEL_CASCADE_DISABLE     non-empty → silent
#   CC_PARALLEL_CASCADE_QUIET       non-empty → silent
#   CC_PARALLEL_CASCADE_STATE_DIR   default /tmp/cc-parallel-cascade
# ================================================================

set -u

# Disable / quiet
if [ -n "${CC_PARALLEL_CASCADE_DISABLE:-}" ] || [ -n "${CC_PARALLEL_CASCADE_QUIET:-}" ]; then
    exit 0
fi

THRESHOLD="${CC_PARALLEL_CASCADE_THRESHOLD:-5}"
WINDOW_SEC="${CC_PARALLEL_CASCADE_WINDOW_SEC:-60}"
STATE_DIR="${CC_PARALLEL_CASCADE_STATE_DIR:-/tmp/cc-parallel-cascade}"
LOG_FILE="$STATE_DIR/events.log"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

INPUT=$(cat)

# Extract tool_response (cancellation message lives here)
RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response // .tool_result // empty' 2>/dev/null)

# Some Claude Code versions wrap tool_response as an object; try common nested fields
if [ -z "$RESPONSE" ]; then
    RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response.output // .tool_response.error // .tool_response.text // empty' 2>/dev/null)
fi

# If no response at all, nothing to count
[ -z "$RESPONSE" ] && exit 0

# Detect the cascade signature
# Pattern: "Cancelled: parallel tool call X errored" (case-insensitive on cancelled)
if printf '%s' "$RESPONSE" | grep -qiE 'Cancelled:[[:space:]]+parallel tool call[[:space:]]+.*errored'; then
    NOW=$(date +%s)
    # Append event timestamp
    printf '%s\n' "$NOW" >> "$LOG_FILE"

    # Compute cutoff
    CUTOFF=$((NOW - WINDOW_SEC))

    # Count events within window and rewrite log to prune old entries
    COUNT=0
    TMP_LOG=$(mktemp)
    while IFS= read -r ts; do
        if [ "$ts" -ge "$CUTOFF" ] 2>/dev/null; then
            printf '%s\n' "$ts" >> "$TMP_LOG"
            COUNT=$((COUNT + 1))
        fi
    done < "$LOG_FILE"
    mv "$TMP_LOG" "$LOG_FILE" 2>/dev/null

    # Warn at threshold
    if [ "$COUNT" -ge "$THRESHOLD" ]; then
        cat >&2 <<EOF

⚠️  Parallel-batch cascade detected: $COUNT cancellation events in the last ${WINDOW_SEC}s.

What this means:
  A single failed tool call in a parallel batch cancels every sibling
  call with "Cancelled: parallel tool call X errored". The model can
  misattribute these cancellations to a user interrupt and may
  fabricate user statements that never happened. See Issue #64047
  for a worked example (25-call cascade → 2-hour fabricated user
  state, zero actual user input).

Operator-side mitigation today:
  1. Reduce parallel batch size to N=3-5 via CLAUDE.md guidance.
  2. Audit transcripts:
       grep -c "parallel tool call.*errored" ~/.claude/projects/*/recent.jsonl
  3. Avoid git / curl / pkill in parallel batches when the
     failure-on-empty case is common — they are the 3 most-cited
     cascade triggers in the cluster reports (#64059 / #64052 / #64047).

Tracking: cc-safe-setup candidate cluster #20.
EOF
    fi
fi

exit 0
