#!/bin/bash
# ================================================================
# parallel-batch-size-limiter.sh — Surface large parallel batches
# ================================================================
# PURPOSE:
#   The companion to parallel-cascade-detector.sh (which fires
#   POST-cascade). This PRE-batch hook detects when a single
#   assistant turn is firing many tool calls in quick succession
#   (within a configurable batch window) and warns the operator
#   BEFORE the batch can cascade.
#
#   Why: a single failed tool call in a parallel batch cancels every
#   sibling call (Issue #64059 / #64052 / #64047). Larger batches
#   have larger cascade blast-radius. Capping batch size from the
#   operator side keeps cascade radius small while the upstream
#   "fan-out, continue on partial failure" semantic is still pending.
#
# DETECTION MODEL:
#   PreToolUse fires per tool call. Same-batch parallel calls fire in
#   quick succession (default within 500ms). This hook records each
#   call's timestamp; on each new fire, it counts calls in the rolling
#   batch window and warns when the count crosses a configurable
#   threshold.
#
# CLUSTER:
#   Candidate cluster #20 — parallel tool batch cancellation cascade
#   Same cluster as parallel-cascade-detector.sh (PostToolUse companion).
#
# TRIGGER: PreToolUse  MATCHER: (any tool)
#
# ENV:
#   CC_PARALLEL_BATCH_LIMITER_THRESHOLD     default 6  (warn at 6+ siblings)
#   CC_PARALLEL_BATCH_LIMITER_WINDOW_MS     default 500
#   CC_PARALLEL_BATCH_LIMITER_DISABLE       non-empty → silent
#   CC_PARALLEL_BATCH_LIMITER_QUIET         non-empty → silent
#   CC_PARALLEL_BATCH_LIMITER_STATE_DIR     default /tmp/cc-parallel-batch
# ================================================================

set -u

# Disable / quiet
if [ -n "${CC_PARALLEL_BATCH_LIMITER_DISABLE:-}" ] || [ -n "${CC_PARALLEL_BATCH_LIMITER_QUIET:-}" ]; then
    exit 0
fi

THRESHOLD="${CC_PARALLEL_BATCH_LIMITER_THRESHOLD:-6}"
WINDOW_MS="${CC_PARALLEL_BATCH_LIMITER_WINDOW_MS:-500}"
STATE_DIR="${CC_PARALLEL_BATCH_LIMITER_STATE_DIR:-/tmp/cc-parallel-batch}"
LOG_FILE="$STATE_DIR/batch.log"
WARN_FILE="$STATE_DIR/last-warn"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Read input (don't fail if jq missing — just exit silently)
INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Current time in milliseconds (portable across GNU and BSD date)
NOW_MS=$(date +%s%3N 2>/dev/null)
if [ -z "$NOW_MS" ] || [ "${#NOW_MS}" -lt 13 ]; then
    # macOS / BSD date doesn't support %N — fall back to seconds * 1000
    NOW_S=$(date +%s)
    NOW_MS=$((NOW_S * 1000))
fi

# Record this fire
printf '%s\n' "$NOW_MS" >> "$LOG_FILE"

# Compute cutoff (NOW - WINDOW_MS)
CUTOFF=$((NOW_MS - WINDOW_MS))

# Count events in window and prune old entries
COUNT=0
TMP_LOG=$(mktemp)
while IFS= read -r ts; do
    # Skip malformed entries
    case "$ts" in
        ''|*[!0-9]*) continue ;;
    esac
    if [ "$ts" -ge "$CUTOFF" ] 2>/dev/null; then
        printf '%s\n' "$ts" >> "$TMP_LOG"
        COUNT=$((COUNT + 1))
    fi
done < "$LOG_FILE"
mv "$TMP_LOG" "$LOG_FILE" 2>/dev/null

# Warn only when threshold is freshly crossed (debounce repeat warnings within
# the same batch — checking last-warn timestamp).
if [ "$COUNT" -ge "$THRESHOLD" ]; then
    LAST_WARN=0
    if [ -f "$WARN_FILE" ]; then
        LAST_WARN=$(cat "$WARN_FILE" 2>/dev/null || echo 0)
    fi
    # Only warn if last warning was outside the current batch window
    if [ "$LAST_WARN" -lt "$CUTOFF" ] 2>/dev/null; then
        printf '%s' "$NOW_MS" > "$WARN_FILE"
        cat >&2 <<EOF

⚠️  Large parallel batch detected: $COUNT tool calls in the last ${WINDOW_MS}ms.

What this means:
  A single failed tool call in this batch will cancel every sibling
  call with "Cancelled: parallel tool call X errored" (Issue #64059
  / #64052 / #64047). Larger batches have larger cascade radius.
  The model may then misattribute the cascade to a user interrupt
  and fabricate user statements that never happened.

Recommended:
  Cap parallel batches at N=3-5 in CLAUDE.md guidance.
  Common non-fatal triggers to keep OUT of parallel batches:
    - git with potentially-invalid revisions (exit 128)
    - curl probes expected to return 404
    - pkill with nothing matching (exit 144)

Tracking: cc-safe-setup candidate cluster #20.
Defense companion: parallel-cascade-detector.sh (PostToolUse).
EOF
    fi
fi

exit 0
