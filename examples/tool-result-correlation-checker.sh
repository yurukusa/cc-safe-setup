#!/bin/bash
# ================================================================
# tool-result-correlation-checker.sh — Detect tool-result misattribution
# ================================================================
# PURPOSE:
#   When Claude Code dispatches parallel tool calls in a single
#   assistant turn, the harness must correlate each `tool_use_id`
#   to exactly one `tool_result` block with the same id. Issue
#   #64095 documents a failure mode where this correlation breaks:
#
#     - A `Skill(...)` call returned, as its results, the outputs
#       of unrelated calls from earlier turns (multiple `Read`s,
#       four `TaskCreate`s, and an `Agent` dispatch).
#
#   This is qualitatively different from cluster 20's cancellation
#   cascade (#64047 / #64052 / #64059) — those produce cancelled
#   batches, this produces *misrouted* results that the model
#   reasons against as if they were the genuine output of the call
#   it actually issued. The model then composes downstream replies
#   from invented observations.
#
#   This hook scans the recent transcript for `tool_use_id` ↔
#   `tool_result` pairing mismatches and surfaces them on stderr.
#   It does NOT prevent misrouting (the routing happens upstream
#   in the harness) — it surfaces the symptom so operators can
#   recognize when the model's tool-output claims may be reasoning
#   against misrouted data.
#
# CLUSTER:
#   Candidate cluster #22 axis 22B (parallel-batch fabrication
#   compounding) — Opus 4.8 pre-execution tool-output fabrication
#   surfaces 6+ filings in 48 hours (#64048 / #64055 / #64065 /
#   #64076 / #64095 / #64103 / #64118), with #64095 specifically
#   documenting envelope leak + out-of-order misattribution.
#
#   Also addresses cluster 20 axis 20B (cancellation message
#   indistinguishability) when a cancelled call's slot is filled
#   by a routed-elsewhere result from another batch.
#
# TRIGGER: PostToolUse  MATCHER: (any tool)
#
# ENV:
#   CC_TOOL_CORRELATION_THRESHOLD   default 1 (warn on first mismatch)
#   CC_TOOL_CORRELATION_WINDOW_SEC  default 60 (per-batch window)
#   CC_TOOL_CORRELATION_DISABLE     non-empty → silent
#   CC_TOOL_CORRELATION_QUIET       non-empty → silent
#   CC_TOOL_CORRELATION_STATE_DIR   default /tmp/cc-tool-correlation
#   CC_TOOL_CORRELATION_TRANSCRIPT  override transcript path (test-only)
# ================================================================

set -u

# Disable / quiet
if [ -n "${CC_TOOL_CORRELATION_DISABLE:-}" ] || [ -n "${CC_TOOL_CORRELATION_QUIET:-}" ]; then
    exit 0
fi

THRESHOLD="${CC_TOOL_CORRELATION_THRESHOLD:-1}"
WINDOW_SEC="${CC_TOOL_CORRELATION_WINDOW_SEC:-60}"
STATE_DIR="${CC_TOOL_CORRELATION_STATE_DIR:-/tmp/cc-tool-correlation}"
LOG_FILE="$STATE_DIR/events.log"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

INPUT=$(cat)

# Locate transcript: prefer env override (for tests), else parse from input
TRANSCRIPT="${CC_TOOL_CORRELATION_TRANSCRIPT:-}"
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi

# If no transcript, nothing to check
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -r "$TRANSCRIPT" ] && exit 0

# Extract the most recent assistant turn's tool_use blocks and the
# corresponding user turn's tool_result blocks. We check the last
# ~30 lines of transcript (enough for one assistant→user round-trip
# even with large parallel batches).
RECENT_LINES=$(tail -n 30 "$TRANSCRIPT" 2>/dev/null)
[ -z "$RECENT_LINES" ] && exit 0

# Collect tool_use_ids from the most recent assistant turn (newest first)
# and tool_result tool_use_ids from the user turn that should answer them.
# Format: one id per line.
USE_IDS=$(printf '%s\n' "$RECENT_LINES" | jq -rR '
    fromjson? |
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    .id
' 2>/dev/null)

RESULT_IDS=$(printf '%s\n' "$RECENT_LINES" | jq -rR '
    fromjson? |
    select(.type == "user") |
    .message.content[]? |
    select(.type == "tool_result") |
    .tool_use_id
' 2>/dev/null)

# If either list is empty, no batch to correlate
[ -z "$USE_IDS" ] && exit 0
[ -z "$RESULT_IDS" ] && exit 0

# Count tool_use ids and tool_result ids; mismatch indicates either:
#   (a) duplicate result for one id (envelope leak)
#   (b) result for an id never used (misrouting from earlier turn)
#   (c) missing result for a used id (lost result)
USE_COUNT=$(printf '%s\n' "$USE_IDS" | grep -c . || true)
RESULT_COUNT=$(printf '%s\n' "$RESULT_IDS" | grep -c . || true)

# Check for results without matching uses (misrouting signal)
ORPHAN_RESULTS=$(comm -13 <(printf '%s\n' "$USE_IDS" | sort -u) <(printf '%s\n' "$RESULT_IDS" | sort -u) | grep -c . || true)

# Check for duplicate result ids (envelope leak signal)
DUP_RESULTS=$(printf '%s\n' "$RESULT_IDS" | sort | uniq -d | grep -c . || true)

# Mismatch detected if either:
#   - there are orphan results (results without matching uses), OR
#   - there are duplicate result ids
MISMATCH=0
if [ "${ORPHAN_RESULTS:-0}" -gt 0 ] || [ "${DUP_RESULTS:-0}" -gt 0 ]; then
    MISMATCH=1
fi

# Record event and check rolling-window count
if [ "$MISMATCH" -eq 1 ]; then
    NOW=$(date +%s)
    printf '%s\n' "$NOW" >> "$LOG_FILE"

    # Prune old events and count
    CUTOFF=$((NOW - WINDOW_SEC))
    COUNT=0
    TMP_LOG=$(mktemp)
    while IFS= read -r ts; do
        if [ "${ts:-0}" -ge "$CUTOFF" ]; then
            printf '%s\n' "$ts" >> "$TMP_LOG"
            COUNT=$((COUNT + 1))
        fi
    done < "$LOG_FILE"
    mv "$TMP_LOG" "$LOG_FILE"

    # Warn if threshold crossed
    if [ "$COUNT" -ge "$THRESHOLD" ]; then
        cat >&2 <<EOF
⚠️  tool-result correlation mismatch detected ($COUNT in last ${WINDOW_SEC}s)
   Recent batch: $USE_COUNT tool_use, $RESULT_COUNT tool_result
   Orphan results (no matching use): $ORPHAN_RESULTS
   Duplicate result ids (envelope leak): $DUP_RESULTS

   This is the symptom shape of cluster #22 axis 22B
   (Opus 4.8 misrouted tool-result envelopes) per Issue #64095.

   Operator action: do NOT trust the model's "I executed X" claims
   from this turn — re-verify any tool-output values manually.
   Consider switching to /model claude-opus-4-7 and dropping to
   single sequential tool calls for the next critical step.

   See: https://github.com/yurukusa/cc-safe-setup/blob/main/docs/cluster-tracker.html#cluster-22
   Silence: export CC_TOOL_CORRELATION_QUIET=1
EOF
    fi
fi

exit 0
