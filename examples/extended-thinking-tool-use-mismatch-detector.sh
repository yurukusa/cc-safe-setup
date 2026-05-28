#!/bin/bash
# ================================================================
# extended-thinking-tool-use-mismatch-detector.sh — Warn when the
#   structural 12B pattern is detected in the trailing transcript:
#   assistant turns with stop_reason="tool_use" but no parseable
#   tool_use block in content (only thinking and/or text blocks).
# ================================================================
# PURPOSE:
#   Issue #62467 documents that when Opus 4.7's extended thinking
#   is active, the assistant turn can carry stop_reason="tool_use"
#   yet emit only a thinking block — no tool_use block reaches the
#   harness parser. The harness then surfaces a "malformed and
#   could not be parsed" notice and retries; in the reporter's
#   sessions ~20 retry prompts accumulated across 6 sessions with
#   no recovery. Output size and special characters are ruled out;
#   the common factor is Opus 4.7 + extended thinking.
#
#   The companion sub-pattern 12A
#   (long-session-malformed-tool-call-detector.sh, PR #406) keys
#   off the literal "malformed and could not be parsed" string in
#   the transcript text. That text marker fires for any cause of
#   the same surface symptom. The 12B detector here keys off the
#   structural mismatch directly — stop_reason vs. content-block
#   absence — so the operator gets sub-pattern-specific naming
#   even when 12A's text marker has not appeared yet (the harness
#   may suppress the parser notice in some configurations) or when
#   it fires together with 12A's marker (both advisories then name
#   the cluster, with 12B specifically calling out the
#   extended-thinking factor and pointing to the workaround at the
#   model layer rather than at the session layer).
#
# TRIGGER: PostToolUse  MATCHER: ""
# CLUSTER: 12 (Tool Call Parsing failures in Opus 4.7)
# SUB-PATTERN: 12B (extended-thinking serialization defect)
#
# BEHAVIOR:
#   - Read transcript_path from PostToolUse hook input.
#   - Scan the trailing LOOKBACK lines for assistant turns.
#   - For each assistant turn, check if .stop_reason == "tool_use"
#     and the .content array contains no element with
#     .type == "tool_use". Count each such mismatch.
#   - If at or above the threshold, emit a one-screen stderr
#     advisory naming sub-pattern 12B and pointing to the
#     model-layer workaround (switch to a variant without
#     extended thinking).
#   - Rate-limit advisory emission per session via a counter
#     file so the warning does not repeat on every PostToolUse
#     after the first detection.
#   - Always exits 0 (advisory only; never blocks tool execution).
#
# CONFIGURATION (env vars):
#   CC_THINKING_MISMATCH_DISABLE     Set to "1" to silence.
#   CC_THINKING_MISMATCH_LOOKBACK    How many recent transcript
#                                    lines to scan. Default 150.
#   CC_THINKING_MISMATCH_THRESHOLD   Minimum mismatches in
#                                    LOOKBACK to fire. Default 2.
#                                    (Single mismatches are rare
#                                    but can occur from unrelated
#                                    serialization edge cases;
#                                    requiring 2 keys off the
#                                    repeated-failure shape
#                                    #62467 actually documents.)
#   CC_THINKING_MISMATCH_COOLDOWN    Minimum tool calls between
#                                    repeat advisories per
#                                    session. Default 30.
#   CC_THINKING_MISMATCH_TRANSCRIPT  Override transcript path
#                                    (used by tests).
#   CC_THINKING_MISMATCH_STATE_DIR   Override state directory
#                                    (used by tests). Default
#                                    /tmp/cc-thinking-mismatch.
#
# UPSTREAM REFERENCES:
#   #62467 (central case: stop_reason="tool_use" with only a
#           thinking block, ~20 retry prompts across 6 sessions,
#           Opus 4.7 + extended thinking)
#   #62123 (broader "retry also failed" central case, 21 reactions)
#   #62344 (in-context few-shot poisoning, sub-pattern 12A)
#   #62700 (spurious malformed notice, sub-pattern 12C)
#
# RECOVERY ON A HIT:
#   The advisory does not recover the session. The known
#   workaround for sub-pattern 12B is at the model layer:
#     - Switch to a Claude Sonnet variant for the task at hand.
#     - Disable extended thinking via the /model command when
#       Opus's standard mode is sufficient.
#   /clear (the 12A recovery) does not fix 12B because the
#   serialization defect re-fires on the next extended-thinking
#   turn even in a fresh session. The advisory's value is in
#   pointing the operator at the correct workaround layer.
# ================================================================

set -u

if [ "${CC_THINKING_MISMATCH_DISABLE:-0}" = "1" ]; then
    exit 0
fi

LOOKBACK="${CC_THINKING_MISMATCH_LOOKBACK:-150}"
THRESHOLD="${CC_THINKING_MISMATCH_THRESHOLD:-2}"
COOLDOWN="${CC_THINKING_MISMATCH_COOLDOWN:-30}"
STATE_DIR="${CC_THINKING_MISMATCH_STATE_DIR:-/tmp/cc-thinking-mismatch}"

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT_PATH="${CC_THINKING_MISMATCH_TRANSCRIPT:-}"
if [ -z "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

SAFE_SESSION=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_' | head -c 80)
[ -z "$SAFE_SESSION" ] && SAFE_SESSION="default"

mkdir -p "$STATE_DIR" 2>/dev/null

COUNTER_FILE="$STATE_DIR/${SAFE_SESSION}.count"
LASTFIRED_FILE="$STATE_DIR/${SAFE_SESSION}.lastfired"

COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Count structural 12B mismatches in the trailing window.
# A mismatch is an assistant turn line where:
#   - stop_reason equals "tool_use" (checked at .stop_reason and
#     .message.stop_reason to handle both common transcript shapes)
#   - the matching content array contains no element with
#     type == "tool_use"
# Each line is parsed independently; lines that fail to parse as
# JSON are silently skipped.
MISMATCHES=$(tail -n "$LOOKBACK" "$TRANSCRIPT_PATH" 2>/dev/null | jq -R -r '
    try (fromjson) catch null | select(. != null) | . as $obj |
    (
        (($obj.stop_reason // $obj.message.stop_reason) == "tool_use")
        and
        (
            (($obj.content // $obj.message.content // []) | type) == "array"
        )
        and
        (
            (($obj.content // $obj.message.content // []) | map(select(.type == "tool_use")) | length) == 0
        )
    ) | select(. == true) | "1"
' 2>/dev/null | wc -l | tr -d ' ')

MISMATCHES="${MISMATCHES:-0}"

if [ "$MISMATCHES" -lt "$THRESHOLD" ]; then
    exit 0
fi

LASTFIRED=$(cat "$LASTFIRED_FILE" 2>/dev/null || echo 0)
SINCE=$((COUNT - LASTFIRED))

if [ "$LASTFIRED" -gt 0 ] && [ "$SINCE" -lt "$COOLDOWN" ]; then
    exit 0
fi

echo "$COUNT" > "$LASTFIRED_FILE"

cat >&2 <<EOF

⚠️  Detected ${MISMATCHES} assistant turn(s) with stop_reason="tool_use"
    but no parseable tool_use block in content, in the trailing
    ${LOOKBACK} transcript lines.

This is the structural signal for sub-pattern 12B
(extended-thinking serialization defect), the case filed in #62467.
When Opus 4.7's extended thinking is active, the assistant turn can
carry stop_reason="tool_use" yet emit only a thinking block — the
tool_use block never reaches the harness parser. The reporter
observed ~20 retry prompts accumulated across 6 sessions before
giving up; output size and special characters were ruled out, and
the common factor was Opus 4.7 + extended thinking.

Sub-pattern 12B is distinct from 12A (in-context few-shot
poisoning, #62344, recovered by \`/clear\`). 12B is at the model
serialization layer, so a fresh session does not recover — the
defect re-fires on the next extended-thinking turn.

Known workarounds (operator-side, at the model layer):
  - Switch to a Claude Sonnet variant for the affected task.
  - Disable extended thinking via the \`/model\` command when
    Opus's standard mode is sufficient for the work.
  - Break the work into smaller sub-tasks that complete without
    the model entering extended thinking.

If a single mismatch in the window is informational, sub-pattern
12B's actual signal is the repeated-failure shape #62467 documents
(the default threshold of 2 keys off that). If you are seeing
mismatches reliably above the threshold, the model layer is in the
state #62467 describes and operator-side hooks cannot recover.

References: #62467 (the extended-thinking-serialization central
case), #62123 (the broader "retry also failed" case, 21 reactions),
Cluster 12 in the cc-safe-setup tracker:
https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html#cluster-tool-call-parsing

Silence: set CC_THINKING_MISMATCH_DISABLE=1.
Tune sensitivity: CC_THINKING_MISMATCH_THRESHOLD (default 2),
                  CC_THINKING_MISMATCH_LOOKBACK (default 150 lines),
                  CC_THINKING_MISMATCH_COOLDOWN (default 30 tool calls).

EOF

exit 0
