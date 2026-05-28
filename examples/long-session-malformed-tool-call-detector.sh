#!/bin/bash
# ================================================================
# long-session-malformed-tool-call-detector.sh — Warn when a
#   "malformed and could not be parsed" marker is detected in the
#   trailing transcript window, surfacing sub-pattern 12A
#   (in-context few-shot poisoning) before the operator hits the
#   "retry also failed" terminal state.
# ================================================================
# PURPOSE:
#   Issue #62344 documents that in a long-running Claude Code
#   session, once one malformed tool call (e.g. a bare
#   `<invoke name="Bash">...</invoke>` with no enclosing
#   `function_calls` wrapper) lands in conversation history,
#   the model anchors on it as in-context few-shot and
#   subsequent same-type tool calls reproduce the broken format
#   deterministically. Self-correction prompts do not recover;
#   only `/clear` (a fresh session with no poisoned history)
#   restores correct behavior. The reporter observed 4
#   consecutive retries all failing identically.
#
#   The harness reports "malformed and could not be parsed" each
#   time. The operator-visible signal is buried in the assistant
#   turn surface; the structural recurrence is invisible until
#   the operator notices the pattern. By then the session may
#   have accumulated significant context that `/clear` will
#   discard.
#
#   This PostToolUse hook scans the trailing window of the
#   transcript for the marker substring and emits a one-screen
#   advisory naming the sub-pattern, the recovery path, and the
#   trade-off (`/clear` discards accumulated context). It does
#   not block tool execution; the failure shape is at the model
#   layer, not the tool layer, and a hook cannot prevent it from
#   the operator side.
#
# TRIGGER: PostToolUse  MATCHER: ""
# CLUSTER: 12 (Tool Call Parsing failures in Opus 4.7)
# SUB-PATTERN: 12A (in-context few-shot poisoning)
#
# BEHAVIOR:
#   - Read transcript_path from PostToolUse hook input.
#   - Scan the trailing LOOKBACK lines for the marker substring
#     "malformed and could not be parsed" (the literal phrase
#     Anthropic's runtime emits).
#   - Count occurrences. If at or above the threshold, emit a
#     one-screen stderr advisory naming sub-pattern 12A and the
#     `/clear` recovery path.
#   - Rate-limit advisory emission per session via a counter
#     file so the warning does not repeat on every PostToolUse
#     after the first detection.
#   - Always exits 0 (advisory only; never blocks tool execution).
#
# CONFIGURATION (env vars):
#   CC_MALFORMED_DETECTOR_DISABLE     Set to "1" to silence.
#   CC_MALFORMED_DETECTOR_LOOKBACK    How many recent transcript
#                                     lines to scan for the
#                                     malformed marker. Default 200.
#   CC_MALFORMED_DETECTOR_THRESHOLD   Minimum occurrences in
#                                     LOOKBACK to fire. Default 1.
#                                     Raise to 2+ if the marker
#                                     appears in legitimate prose.
#   CC_MALFORMED_DETECTOR_COOLDOWN    Minimum tool calls between
#                                     repeat advisories per
#                                     session. Default 50.
#   CC_MALFORMED_DETECTOR_TRANSCRIPT  Override transcript path
#                                     (used by tests).
#   CC_MALFORMED_DETECTOR_STATE_DIR   Override state directory
#                                     (used by tests). Default
#                                     /tmp/cc-malformed-detector.
#
# UPSTREAM REFERENCES:
#   #62123 (central case, 21 reactions: "tool call could not be
#           parsed; retry also failed" on Opus 4.7)
#   #62344 (in-context few-shot poisoning: 4 consecutive retries
#           all fail identically; only /clear recovers)
#   #62467 (extended-thinking serialization defect, a different
#           root-cause hypothesis for the same surface symptom)
#   #62700 (spurious malformed notice — tool actually succeeded)
#   #49747 (legacy XML format mix precursor, filed 2026-04-17)
#
# RECOVERY ON A HIT:
#   The advisory does not recover the session. The known recovery
#   for sub-pattern 12A is `/clear` (a fresh session with no
#   poisoned history). The trade-off is that `/clear` discards
#   the accumulated session context. The advisory's value is in
#   giving the operator a chance to checkpoint the active work
#   to disk *before* deciding whether to `/clear`.
# ================================================================

set -u

if [ "${CC_MALFORMED_DETECTOR_DISABLE:-0}" = "1" ]; then
    exit 0
fi

LOOKBACK="${CC_MALFORMED_DETECTOR_LOOKBACK:-200}"
THRESHOLD="${CC_MALFORMED_DETECTOR_THRESHOLD:-1}"
COOLDOWN="${CC_MALFORMED_DETECTOR_COOLDOWN:-50}"
STATE_DIR="${CC_MALFORMED_DETECTOR_STATE_DIR:-/tmp/cc-malformed-detector}"

INPUT=$(cat 2>/dev/null || true)

TRANSCRIPT_PATH="${CC_MALFORMED_DETECTOR_TRANSCRIPT:-}"
if [ -z "$TRANSCRIPT_PATH" ]; then
    TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

# Sanitize session id for use as a filename
SAFE_SESSION=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_' | head -c 80)
[ -z "$SAFE_SESSION" ] && SAFE_SESSION="default"

mkdir -p "$STATE_DIR" 2>/dev/null

COUNTER_FILE="$STATE_DIR/${SAFE_SESSION}.count"
LASTFIRED_FILE="$STATE_DIR/${SAFE_SESSION}.lastfired"

# Increment the per-session tool-call counter.
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Look for the marker substring in the trailing window.
MATCHES=$(tail -n "$LOOKBACK" "$TRANSCRIPT_PATH" 2>/dev/null | grep -c 'malformed and could not be parsed' || true)
MATCHES="${MATCHES:-0}"

if [ "$MATCHES" -lt "$THRESHOLD" ]; then
    exit 0
fi

# Cooldown: do not refire within COOLDOWN tool calls of the last advisory.
LASTFIRED=$(cat "$LASTFIRED_FILE" 2>/dev/null || echo 0)
SINCE=$((COUNT - LASTFIRED))

if [ "$LASTFIRED" -gt 0 ] && [ "$SINCE" -lt "$COOLDOWN" ]; then
    exit 0
fi

echo "$COUNT" > "$LASTFIRED_FILE"

# Emit advisory.
cat >&2 <<EOF

⚠️  Detected ${MATCHES} occurrence(s) of "malformed and could not be parsed"
    in the trailing ${LOOKBACK} transcript lines.

This is the surface signal for sub-pattern 12A (in-context few-shot
poisoning), the cluster filed in #62344. Once one malformed tool call
lands in conversation history, the model anchors on it as in-context
few-shot and subsequent same-type calls reproduce the broken format
deterministically. The reporter observed 4 consecutive retries all
failing identically. Self-correction prompts ("be more careful", "send
one call at a time") do not recover.

Known recovery: \`/clear\` (a fresh session with no poisoned history).
The trade-off is that \`/clear\` discards the accumulated session
context. Consider checkpointing the active work to disk *before*
deciding whether to \`/clear\`.

If retries are still succeeding for you, this advisory is informational
— the structural recurrence may not have triggered in your session yet.
If retries have started failing identically, the session is likely
poisoned and \`/clear\` will be needed to restore correct behavior.

References: #62344 (the central in-context-poisoning analysis),
#62123 (the broader "retry also failed" central case), Cluster 12 in
the cc-safe-setup tracker:
https://yurukusa.github.io/cc-safe-setup/cluster-tracker.html#cluster-tool-call-parsing

Silence: set CC_MALFORMED_DETECTOR_DISABLE=1.
Tune sensitivity: CC_MALFORMED_DETECTOR_THRESHOLD (default 1),
                  CC_MALFORMED_DETECTOR_LOOKBACK (default 200 lines),
                  CC_MALFORMED_DETECTOR_COOLDOWN (default 50 tool calls).

EOF

exit 0
