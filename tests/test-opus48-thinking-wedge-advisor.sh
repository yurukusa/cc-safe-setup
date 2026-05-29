#!/bin/bash
# Tests for opus48-thinking-wedge-advisor.sh (Cluster 13 Axis G)
# Covers: transition detection, transcript precondition, fail-open,
# environment variables, edge cases.

HOOK="examples/opus48-thinking-wedge-advisor.sh"
PASS=0 FAIL=0

TEST_HOME=$(mktemp -d)
TEST_TRANSCRIPT_DIR="$TEST_HOME/transcripts"
mkdir -p "$TEST_TRANSCRIPT_DIR"
trap 'rm -rf "$TEST_HOME"' EXIT

write_transcript() {
    local f="$TEST_TRANSCRIPT_DIR/$1"; shift
    : > "$f"
    for line in "$@"; do
        printf '%s\n' "$line" >> "$f"
    done
    echo "$f"
}

run_hook() {
    local payload="$1"; shift
    HOME="$TEST_HOME" env "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  got: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

signed_thinking_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"some reasoning","signature":"sigABCDEF1234567890"}]}}'
empty_signed_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"longerSignatureFFFF1234"}]}}'
unsigned_thinking_line='{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":""}]}}'
text_only_line='{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}'
user_line='{"type":"user","message":{"content":[{"type":"text","text":"hi"}]}}'

HIST="$TEST_HOME/history"

# ---- Group 1: basic event handling and fail-open ----

# Test 1: empty input → exit 0, no advisory
OUT=$(run_hook '{}' CC_CLUSTER_13G_HISTORY_FILE="$HIST")
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
assert_not_contains "empty input no advisory" "$OUT" "Cluster 13G"

# Test 2: invalid JSON → exit 0
OUT=$(run_hook 'not json' CC_CLUSTER_13G_HISTORY_FILE="$HIST")
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# Test 3: no model in event or env → exit 0
OUT=$(run_hook '{"event":"Notification"}' CC_CLUSTER_13G_HISTORY_FILE="$HIST")
RC=$?
assert_exit "no model exit 0" "$RC" "0"
assert_not_contains "no model no advisory" "$OUT" "Cluster 13G"

# ---- Group 2: history-file priming (no prior model → silent) ----

rm -f "$HIST"
# Test 4: first observation of 4.7 with no history → silent, records model
F=$(write_transcript "4.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-7"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
RC=$?
assert_exit "first observation exit 0" "$RC" "0"
assert_not_contains "first observation no advisory" "$OUT" "Cluster 13G"
RECORDED=$(cat "$HIST" 2>/dev/null)
[ "$RECORDED" = "claude-opus-4-7" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: history not recorded (got '$RECORDED')"; }

# ---- Group 3: 4.7 → 4.8 transition with signed thinking blocks (advisory fires) ----

# Test 5: 4.7 → 4.8 transition with signed thinking blocks → advisory
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "5.jsonl" "$signed_thinking_line" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
RC=$?
assert_exit "13G transition exit 0" "$RC" "0"
assert_contains "13G transition advisory fires" "$OUT" "Cluster 13G transition detected"
assert_contains "13G transition lists prior model" "$OUT" "claude-opus-4-7"
assert_contains "13G transition lists current model" "$OUT" "claude-opus-4-8"
assert_contains "13G transition mentions hard 400" "$OUT" "must remain as they were"
assert_contains "13G transition recommends staying on 4.7" "$OUT" "/model"

# Test 6: 4.7 → 4.8 transition with empty-text-but-signed blocks → advisory
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "6.jsonl" "$empty_signed_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_contains "13G fires on empty-signed blocks too" "$OUT" "Cluster 13G transition detected"

# ---- Group 4: precondition gating (no signed blocks → silent) ----

# Test 7: 4.7 → 4.8 transition but no signed thinking blocks → silent
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "7.jsonl" "$unsigned_thinking_line" "$text_only_line" "$user_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
RC=$?
assert_exit "no signed blocks exit 0" "$RC" "0"
assert_not_contains "no signed blocks no advisory" "$OUT" "Cluster 13G"

# Test 8: 4.7 → 4.8 transition with empty transcript file → silent
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "8.jsonl")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_not_contains "empty transcript no advisory" "$OUT" "Cluster 13G"

# ---- Group 5: non-13G transitions gated out ----

# Test 9: same model (4.7 → 4.7) → silent
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "9.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-7"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_not_contains "same model no advisory" "$OUT" "Cluster 13G"

# Test 10: 4.8 → 4.7 (reverse direction) → silent
printf '%s' "claude-opus-4-8" > "$HIST"
F=$(write_transcript "10.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-7"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_not_contains "reverse direction no advisory" "$OUT" "Cluster 13G"

# Test 11: 4.6 → 4.7 (unrelated transition) → silent
printf '%s' "claude-opus-4-6" > "$HIST"
F=$(write_transcript "11.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-7"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_not_contains "unrelated transition no advisory" "$OUT" "Cluster 13G"

# Test 12: sonnet → opus-4-8 → silent
printf '%s' "claude-sonnet-4-6" > "$HIST"
F=$(write_transcript "12.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_not_contains "sonnet→opus-4-8 no advisory" "$OUT" "Cluster 13G"

# ---- Group 6: model name variants ----

# Test 13: API-style "claude-opus-4-7" → "claude-opus-4-8" matches
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "13.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_contains "API-style name matches" "$OUT" "Cluster 13G transition"

# Test 14: short-form "Opus 4.7" → "Opus 4.8" matches (dot/space separator)
printf '%s' "Opus 4.7" > "$HIST"
F=$(write_transcript "14.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"Opus 4.8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
assert_contains "short-form name matches" "$OUT" "Cluster 13G transition"

# Test 15: model from CLAUDE_MODEL env (no body model)
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "15.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F" \
    CLAUDE_MODEL="claude-opus-4-8")
assert_contains "model from env matches" "$OUT" "Cluster 13G transition"

# ---- Group 7: environment variables ----

# Test 16: CC_CLUSTER_13G_DISABLE=1 disables hook
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "16.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F" \
    CC_CLUSTER_13G_DISABLE=1)
assert_not_contains "DISABLE silences advisory" "$OUT" "Cluster 13G"

# Test 17: CC_CLUSTER_13G_VERBOSE=1 includes signature lengths
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "17.jsonl" "$signed_thinking_line" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F" \
    CC_CLUSTER_13G_VERBOSE=1)
assert_contains "VERBOSE includes signature lengths" "$OUT" "signature lengths"

# Test 18: CC_CLUSTER_13G_FORCE=1 fires even without 4.7→4.8 transition
printf '%s' "claude-sonnet-4-6" > "$HIST"
F=$(write_transcript "18.jsonl" "$signed_thinking_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-sonnet-4-7"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F" \
    CC_CLUSTER_13G_FORCE=1)
assert_contains "FORCE bypasses transition check" "$OUT" "Cluster 13G transition"

# ---- Group 8: state persistence ----

# Test 19: history file updated after each invocation
rm -f "$HIST"
F=$(write_transcript "19.jsonl" "$signed_thinking_line")
run_hook '{"event":"Notification","model":"claude-opus-4-7"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F" >/dev/null 2>&1
RECORDED=$(cat "$HIST" 2>/dev/null)
[ "$RECORDED" = "claude-opus-4-7" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: history not updated on first call"; }

run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F" >/dev/null 2>&1
RECORDED=$(cat "$HIST" 2>/dev/null)
[ "$RECORDED" = "claude-opus-4-8" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: history not updated on second call"; }

# ---- Group 9: malformed transcript fail-open ----

# Test 20: transcript with malformed JSON lines mixed with valid signed blocks
printf '%s' "claude-opus-4-7" > "$HIST"
F=$(write_transcript "20.jsonl" "not valid json" "$signed_thinking_line" '{"incomplete":' "$user_line")
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="$F")
RC=$?
assert_exit "malformed lines exit 0" "$RC" "0"
assert_contains "malformed lines still find valid signed block" "$OUT" "Cluster 13G transition"

# Test 21: non-existent transcript file → silent fail-open
printf '%s' "claude-opus-4-7" > "$HIST"
OUT=$(run_hook '{"event":"Notification","model":"claude-opus-4-8"}' \
    CC_CLUSTER_13G_HISTORY_FILE="$HIST" \
    CC_CLUSTER_13G_TRANSCRIPT="/tmp/does-not-exist-13g.jsonl")
RC=$?
assert_exit "missing transcript exit 0" "$RC" "0"
assert_not_contains "missing transcript no advisory" "$OUT" "Cluster 13G"

# ---- Summary ----

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
exit "$FAIL"
