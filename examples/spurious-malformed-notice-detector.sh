#!/bin/bash
# ================================================================
# spurious-malformed-notice-detector.sh — Warn when "malformed
#   and could not be parsed" notices co-occur with successful
#   tool executions in the trailing transcript window, signalling
#   sub-pattern 12C (the harness-layer spurious notice).
# ================================================================
# PURPOSE:
#   Issue #62700 documents a case where, after most tool calls
#   (Bash / Edit / Write), the assistant turn is immediately
#   followed by a system message "Your tool call was malformed
#   and could not be parsed. Please retry." — yet the tool
#   actually executed correctly (git commit/push/cherry-pick,
#   gh queries, file writes all produced normal output and took
#   effect). Sometimes the spurious notice is accompanied by
#   "[Request interrupted by user]" and the conversation appears
#   to hang, requiring repeated manual "continue".
#
#   The other Cluster 12 sub-pattern detectors key off the same
#   surface marker but recommend different recoveries:
#     - 12A (#62344) → /clear to drop poisoned history
#     - 12B (#62467) → switch model / disable extended thinking
#   12C is at the harness/streaming layer — the tool succeeded
#   and the notice is the bug. The recovery is the opposite of
#   12A/12B: do NOT /clear (it would discard accumulated context
#   for no benefit) and do NOT switch model (the inference is
#   working correctly). Verify the tool output is correct (it
#   likely is) and proceed.
#
#   This hook fires only when the surface marker AND successful
#   tool_result blocks co-occur in the same window, so it does
#   not fire on the 12A "retry also failed" terminal state.
#
# TRIGGER: PostToolUse  MATCHER: ""
# CLUSTER: 12 (Tool Call Parsing failures in Opus 4.7)
# SUB-PATTERN: 12C (spurious malformed notice; harness-layer)
#
# BEHAVIOR:
#   - Read transcript_path from PostToolUse hook input.
#   - Scan the trailing LOOKBACK lines.
#   - Count marker occurrences ("malformed and could not be
#     parsed", the literal phrase Anthropic's runtime emits).
#   - Count successful tool_result blocks in the same window
#     (.type == "tool_result" and .is_error is not true).
#   - If markers >= MARKER_THRESHOLD AND successes >= markers,
#     emit a one-screen stderr advisory naming sub-pattern 12C
#     and the "verify output, ignore notice" recovery path.
#   - Rate-limit advisory emission per session via a counter
#     file so the warning does not repeat on every PostToolUse
#     after the first detection.
#   - Always exits 0 (advisory only; never blocks tool execution).
#
# WHY THE CO-OCCURRENCE CHECK:
#   The 12A detector fires on the marker alone because the
#   recovery (/clear) is appropriate for any cause of the marker
#   if retries are failing. 12C is the opposite case — the
#   marker is firing while retries are succeeding, so /clear is
#   the wrong recovery. The co-occurrence of marker + successful
#   tool_result is the structural signal that distinguishes the
#   harness-layer false-positive from the model-layer failure.
#
#   In practice 12A and 12C may both fire on the same session
#   (the marker is present and tools are succeeding, but the
#   operator should be aware of both possibilities). That is
#   intended: 12A advises checkpoint + /clear in case retries
#   start failing, 12C confirms the current state and points at
#   the harness layer rather than the session layer.
#
# CONFIGURATION (env vars):
#   CC_SPURIOUS_MALFORMED_DISABLE       Set to "1" to silence.
#   CC_SPURIOUS_MALFORMED_LOOKBACK      How many recent transcript
#                                       lines to scan. Default 200.
#   CC_SPURIOUS_MALFORMED_THRESHOLD     Minimum marker occurrences
#                                       in LOOKBACK to fire.
#                                       Default 1.
#   CC_SPURIOUS_MALFORMED_COOLDOWN      Minimum tool calls between
#                                       repeat advisories per
#                                       session. Default 30.
#   CC_SPURIOUS_MALFORMED_TRANSCRIPT    Override transcript path
#                                       (used by tests).
#   CC_SPURIOUS_MALFORMED_STATE_DIR     Override state directory
#                                       (used by tests). Default
#                                       /tmp/cc-spurious-malformed.
#
# UPSTREAM REFERENCES:
#   #62700 (central case: spurious notice, tools execute
#           correctly, accompanied by "[Request interrupted by
#           user]" and apparent session hangs)
#   #62123 (broader "retry also failed" central case, 21 reactions)
#   #62344 (sub-pattern 12A, in-context few-shot poisoning)
#   #62467 (sub-pattern 12B, extended-thinking serialization)
#
# RECOVERY ON A HIT:
#   The advisory points operators at the verification path:
#     - Verify the tool output (the most recent tool_result
#       block) is what you expected. If yes, the notice is
#       spurious — ignore it and proceed.
#     - Do NOT /clear (would discard context for no benefit).
#     - Do NOT switch model (inference is working correctly).
#     - If session appears to hang, type "continue" to advance
#       (per the #62700 reporter's workaround).
#   The defect is at the streaming/parsing layer in the harness;
#   operator-side hooks cannot recover it, only flag it so the
#   operator stops applying the wrong recoveries.
# ================================================================

set -u

if [ "${CC_SPURIOUS_MALFORMED_DISABLE:-0}" = "1" ]; then
    exit 0
fi

LOOKBACK="${CC_SPURIOUS_MALFORMED_LOOKBACK:-200}"
THRESHOLD="${CC_SPURIOUS_MALFORMED_THRESHOLD:-1}"
COOLDOWN="${CC_SPURIOUS_MALFORMED_COOLDOWN:-30}"
STATE_DIR="${CC_SPURIOUS_MALFORMED_STATE_DIR:-/tmp/cc-spurious-malformed}"

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT_PATH="${CC_SPURIOUS_MALFORMED_TRANSCRIPT:-}"
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

TAIL_WINDOW=$(tail -n "$LOOKBACK" "$TRANSCRIPT_PATH" 2>/dev/null || true)

# Count marker occurrences in the trailing window.
MARKERS=$(printf '%s\n' "$TAIL_WINDOW" | grep -c 'malformed and could not be parsed' || true)
MARKERS="${MARKERS:-0}"

if [ "$MARKERS" -lt "$THRESHOLD" ]; then
    exit 0
fi

# Count successful tool_result blocks in the same window.
# A tool_result is "successful" when .is_error is absent or not true.
# Each transcript line is parsed independently; non-JSON lines are
# silently skipped. Both top-level and .message.content shapes are
# checked to handle the common Claude Code transcript variants.
SUCCESSES=$(printf '%s\n' "$TAIL_WINDOW" | jq -R -r '
    try (fromjson) catch null | select(. != null) | . as $obj |
    (($obj.content // $obj.message.content // [])) as $blocks |
    if ($blocks | type) == "array" then
        ($blocks
            | map(select(.type == "tool_result" and ((.is_error // false) != true)))
            | length)
    else
        0
    end
' 2>/dev/null | awk 'BEGIN{s=0} {s+=$0} END{print s+0}')

SUCCESSES="${SUCCESSES:-0}"

# 12C signature: marker fires alongside at least as many successful
# tool_result blocks. If successes < markers, the cluster is more
# likely 12A (retries actually failing) and the 12C advisory would
# be misleading — stay silent and let the 12A hook surface the case.
if [ "$SUCCESSES" -lt "$MARKERS" ]; then
    exit 0
fi

LASTFIRED=$(cat "$LASTFIRED_FILE" 2>/dev/null || echo 0)
SINCE=$((COUNT - LASTFIRED))

if [ "$LASTFIRED" -gt 0 ] && [ "$SINCE" -lt "$COOLDOWN" ]; then
    exit 0
fi

echo "$COUNT" > "$LASTFIRED_FILE"

cat >&2 <<EOF

⚠️  Detected ${MARKERS} "malformed and could not be parsed" notice(s)
    alongside ${SUCCESSES} successful tool_result block(s) in the
    trailing ${LOOKBACK} transcript lines.

This is the signature for sub-pattern 12C (spurious malformed notice
at the harness/streaming layer), the case filed in #62700. After
most tool calls (Bash / Edit / Write), the assistant turn is
immediately followed by the malformed-parse notice, yet the tool
actually executed correctly — git commit/push, gh queries, file
writes all produced normal output and took effect. Sometimes the
spurious notice is accompanied by "[Request interrupted by user]"
and the conversation appears to hang, requiring repeated manual
"continue".

Sub-pattern 12C is distinct from:
  - 12A (#62344, in-context few-shot poisoning) → /clear to recover.
    12A fires when retries genuinely fail and the broken format is
    reproduced. The current window shows successful tool_results,
    so /clear would discard accumulated context for no benefit.
  - 12B (#62467, extended-thinking serialization defect) → switch
    model / disable extended thinking. 12B fires when the assistant
    turn carries stop_reason="tool_use" with no parseable tool_use
    block. The current window has successful tool_results, so the
    model-layer workaround is not the right recovery.

Recommended verification path for 12C:
  1. Verify the most recent tool_result block(s) in your session.
     If the output is what you expected, the notice is spurious —
     the tool succeeded and the harness misclassified it.
  2. Proceed with your work. Do NOT /clear and do NOT switch model;
     both would burn context for a defect that is not in your
     session or your model.
  3. If the session appears to hang, type "continue" to advance
     (per the #62700 reporter's workaround).
  4. Consider filing on #62700 to add your environment details
     (plugins, hooks, MCP servers); the streaming-layer hypothesis
     is open and your data may help isolate it.

If retries ARE failing for you in addition to the notice, the
session is more likely 12A — checkpoint your active work to disk
and \`/clear\`. The 12A advisory (long-session-malformed-tool-call-
detector.sh, PR #406) covers that case.

References: #62700 (the spurious-notice central case), #62123 (the
broader "retry also failed" central case), Cluster 12 in the
cc-safe-setup tracker:
https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html#cluster-tool-call-parsing

Silence: set CC_SPURIOUS_MALFORMED_DISABLE=1.
Tune sensitivity: CC_SPURIOUS_MALFORMED_THRESHOLD (default 1),
                  CC_SPURIOUS_MALFORMED_LOOKBACK (default 200 lines),
                  CC_SPURIOUS_MALFORMED_COOLDOWN (default 30 tool calls).

EOF

exit 0
