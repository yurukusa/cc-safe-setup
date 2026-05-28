#!/bin/bash
# Tests for extended-thinking-tool-use-mismatch-detector.sh
HOOK="examples/extended-thinking-tool-use-mismatch-detector.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
STATE_DIR="$TMPDIR/state"
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

reset_state() { rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"; }

mk_input() {
    local transcript="$1" sid="${2:-test-session}"
    printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript" "$sid"
}

# A 12B-shape assistant turn line (top-level fields).
mk_12b_top() {
    printf '{"stop_reason":"tool_use","content":[{"type":"thinking","text":"...thinking..."}]}\n'
}

# A 12B-shape assistant turn line (nested under .message, the
# common Claude Code transcript shape).
mk_12b_nested() {
    printf '{"message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"thinking","text":"x"}]}}\n'
}

# A healthy assistant turn: stop_reason="tool_use" AND tool_use
# block present in content. Must NOT count as mismatch.
mk_healthy() {
    printf '{"message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"thinking","text":"x"},{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}\n'
}

# An end_turn line: stop_reason="end_turn", not relevant.
mk_end_turn() {
    printf '{"message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}\n'
}

# Test 1: No transcript path → silent pass
reset_state
OUT=$(echo '{}' | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no transcript silent" "$OUT" "sub-pattern 12B"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Transcript exists but only healthy turns → silent pass
reset_state
TR="$TMPDIR/t2.jsonl"
mk_healthy > "$TR"
mk_healthy >> "$TR"
mk_end_turn >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "healthy only silent" "$OUT" "sub-pattern 12B"
assert_exit "healthy only exit 0" "$RC" "0"

# Test 3: One 12B mismatch (below default threshold 2) → silent
reset_state
TR="$TMPDIR/t3.jsonl"
mk_12b_nested > "$TR"
mk_healthy >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "one mismatch below threshold silent" "$OUT" "sub-pattern 12B"
assert_exit "one mismatch exit 0" "$RC" "0"

# Test 4: Two 12B mismatches → advisory fires (default threshold)
reset_state
TR="$TMPDIR/t4.jsonl"
mk_12b_nested > "$TR"
mk_healthy >> "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "two mismatches fire advisory" "$OUT" "sub-pattern 12B"
assert_contains "advisory cites #62467" "$OUT" "#62467"
assert_contains "advisory cites #62123" "$OUT" "#62123"
assert_contains "advisory mentions extended thinking" "$OUT" "extended thinking"
assert_contains "advisory mentions /model" "$OUT" "/model"
assert_contains "advisory cites cluster tracker" "$OUT" "cluster-tracker"
assert_exit "two mismatches exit 0" "$RC" "0"

# Test 5: Top-level (non-nested) shape also detected
reset_state
TR="$TMPDIR/t5.jsonl"
mk_12b_top > "$TR"
mk_12b_top >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "top-level shape detected" "$OUT" "sub-pattern 12B"
assert_contains "advisory shows occurrence count" "$OUT" "2 assistant turn"
assert_exit "top-level shape exit 0" "$RC" "0"

# Test 6: Mixed top-level and nested shapes — both counted
reset_state
TR="$TMPDIR/t6.jsonl"
mk_12b_top > "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "mixed shapes detected" "$OUT" "sub-pattern 12B"
assert_exit "mixed shapes exit 0" "$RC" "0"

# Test 7: Disabled via env → silent even with mismatches
reset_state
TR="$TMPDIR/t7.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_DISABLE=1 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable env silences" "$OUT" "sub-pattern 12B"
assert_exit "disable env exit 0" "$RC" "0"

# Test 8: Threshold raised to 3 with only 2 mismatches → silent
reset_state
TR="$TMPDIR/t8.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_THRESHOLD=3 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "threshold 3 with 2 silent" "$OUT" "sub-pattern 12B"
assert_exit "threshold 3 with 2 exit 0" "$RC" "0"

# Test 9: Threshold lowered to 1 with one mismatch → advisory fires
reset_state
TR="$TMPDIR/t9.jsonl"
mk_12b_nested > "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_THRESHOLD=1 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "threshold 1 with 1 fires" "$OUT" "sub-pattern 12B"
assert_exit "threshold 1 with 1 exit 0" "$RC" "0"

# Test 10: Cooldown — second call within cooldown stays silent
reset_state
TR="$TMPDIR/t10.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
OUT1=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
OUT2=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "first call within cooldown fires" "$OUT1" "sub-pattern 12B"
assert_not_contains "second call within cooldown silent" "$OUT2" "sub-pattern 12B"

# Test 11: Cooldown — cross cooldown threshold and the advisory refires
reset_state
TR="$TMPDIR/t11.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
OUT1=$(mk_input "$TR" | CC_THINKING_MISMATCH_COOLDOWN=2 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
# Two no-op calls advance the counter
mk_input "$TR" | CC_THINKING_MISMATCH_COOLDOWN=2 CC_THINKING_MISMATCH_THRESHOLD=999 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>/dev/null
mk_input "$TR" | CC_THINKING_MISMATCH_COOLDOWN=2 CC_THINKING_MISMATCH_THRESHOLD=999 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>/dev/null
OUT2=$(mk_input "$TR" | CC_THINKING_MISMATCH_COOLDOWN=2 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "first call fires" "$OUT1" "sub-pattern 12B"
assert_contains "third call past cooldown fires again" "$OUT2" "sub-pattern 12B"

# Test 12: Different sessions have independent state
reset_state
TR="$TMPDIR/t12.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
OUT_A=$(mk_input "$TR" "session-A" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
OUT_B=$(mk_input "$TR" "session-B" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "session A fires" "$OUT_A" "sub-pattern 12B"
assert_contains "session B fires independently" "$OUT_B" "sub-pattern 12B"

# Test 13: Lookback window excludes earlier mismatches
reset_state
TR="$TMPDIR/t13.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
# Pad with healthy turns so the mismatches fall outside the lookback
for i in $(seq 1 50); do
    mk_healthy >> "$TR"
done
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_LOOKBACK=10 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "lookback excludes old mismatches" "$OUT" "sub-pattern 12B"
assert_exit "lookback exclude exit 0" "$RC" "0"

# Test 14: Lookback window includes recent mismatches
reset_state
TR="$TMPDIR/t14.jsonl"
for i in $(seq 1 5); do
    mk_healthy >> "$TR"
done
mk_12b_nested >> "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_LOOKBACK=5 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "lookback includes recent" "$OUT" "sub-pattern 12B"
assert_exit "lookback include exit 0" "$RC" "0"

# Test 15: Non-JSON lines in transcript are skipped silently
reset_state
TR="$TMPDIR/t15.jsonl"
echo "not json at all" > "$TR"
mk_12b_nested >> "$TR"
mk_12b_nested >> "$TR"
echo "another garbage line" >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "non-json lines tolerated" "$OUT" "sub-pattern 12B"
assert_exit "non-json tolerated exit 0" "$RC" "0"

# Test 16: stop_reason="end_turn" (not "tool_use") does NOT count
reset_state
TR="$TMPDIR/t16.jsonl"
# End-turn lines with no tool_use block — must not be counted
mk_end_turn > "$TR"
mk_end_turn >> "$TR"
mk_end_turn >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_THRESHOLD=1 CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "end_turn not counted" "$OUT" "sub-pattern 12B"
assert_exit "end_turn exit 0" "$RC" "0"

# Test 17: Missing transcript file → silent pass
reset_state
OUT=$(mk_input "/nonexistent/transcript.jsonl" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "missing transcript silent" "$OUT" "sub-pattern 12B"
assert_exit "missing transcript exit 0" "$RC" "0"

# Test 18: Advisory mentions Sonnet workaround
reset_state
TR="$TMPDIR/t18.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "advisory mentions Sonnet workaround" "$OUT" "Sonnet"

# Test 19: Advisory differentiates from sub-pattern 12A
reset_state
TR="$TMPDIR/t19.jsonl"
mk_12b_nested > "$TR"
mk_12b_nested >> "$TR"
OUT=$(mk_input "$TR" | CC_THINKING_MISMATCH_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "advisory differentiates from 12A" "$OUT" "12A"
assert_contains "advisory differentiates from clear" "$OUT" "fresh session does not recover"

echo ""
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
