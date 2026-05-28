#!/bin/bash
# Tests for spurious-malformed-notice-detector.sh
HOOK="examples/spurious-malformed-notice-detector.sh"
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

# A user-turn line carrying a successful tool_result block
# (no is_error, or is_error=false). This is the "tool actually
# succeeded" half of the 12C signature.
mk_success_result() {
    printf '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}\n'
}

# A user-turn line carrying a tool_result with is_error=false
# explicitly set. Must still count as success.
mk_success_result_explicit() {
    printf '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}\n'
}

# A user-turn line carrying a tool_result with is_error=true.
# Must NOT count as success.
mk_failed_result() {
    printf '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"err","is_error":true}]}}\n'
}

# A top-level (non-.message) tool_result line — must be detected too.
mk_success_result_top() {
    printf '{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"ok"}]}\n'
}

# A system-style line carrying the spurious-malformed marker.
mk_marker() {
    printf '{"role":"system","content":"Your tool call was malformed and could not be parsed. Please retry."}\n'
}

# An ordinary assistant turn with no marker.
mk_plain() {
    printf '{"message":{"role":"assistant","content":"hello"}}\n'
}

# Test 1: No transcript path → silent pass
reset_state
OUT=$(echo '{}' | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no transcript silent" "$OUT" "sub-pattern 12C"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Missing transcript file → silent pass
reset_state
OUT=$(mk_input "/nonexistent/transcript.jsonl" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "missing transcript silent" "$OUT" "sub-pattern 12C"
assert_exit "missing transcript exit 0" "$RC" "0"

# Test 3: No marker, only successes → silent pass
reset_state
TR="$TMPDIR/t3.jsonl"
mk_success_result > "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no marker silent" "$OUT" "sub-pattern 12C"
assert_exit "no marker exit 0" "$RC" "0"

# Test 4: Marker present but no successful tool_results → silent
# (this is the 12A-shaped state — let the 12A hook handle it)
reset_state
TR="$TMPDIR/t4.jsonl"
mk_marker > "$TR"
mk_marker >> "$TR"
mk_failed_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "marker without success silent" "$OUT" "sub-pattern 12C"
assert_exit "marker without success exit 0" "$RC" "0"

# Test 5: One marker + one success → 12C advisory fires
reset_state
TR="$TMPDIR/t5.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "marker + success fires advisory" "$OUT" "sub-pattern 12C"
assert_contains "advisory cites #62700" "$OUT" "#62700"
assert_contains "advisory cites #62123" "$OUT" "#62123"
assert_contains "advisory differentiates from 12A" "$OUT" "12A"
assert_contains "advisory differentiates from 12B" "$OUT" "12B"
assert_contains "advisory warns not to /clear" "$OUT" "Do NOT /clear"
assert_contains "advisory cites cluster tracker" "$OUT" "cluster-tracker"
assert_exit "marker + success exit 0" "$RC" "0"

# Test 6: Multiple markers and at least as many successes → fires
reset_state
TR="$TMPDIR/t6.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
mk_marker >> "$TR"
mk_success_result >> "$TR"
mk_marker >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "3 markers + 3 successes fires" "$OUT" "sub-pattern 12C"
assert_contains "advisory shows marker count" "$OUT" "3 \"malformed"
assert_contains "advisory shows success count" "$OUT" "3 successful"
assert_exit "3+3 exit 0" "$RC" "0"

# Test 7: Marker count > success count → silent (the 12A case)
reset_state
TR="$TMPDIR/t7.jsonl"
mk_marker > "$TR"
mk_marker >> "$TR"
mk_marker >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "3 markers + 1 success silent" "$OUT" "sub-pattern 12C"
assert_exit "3+1 exit 0" "$RC" "0"

# Test 8: Equal marker and success counts → fires (boundary)
reset_state
TR="$TMPDIR/t8.jsonl"
mk_marker > "$TR"
mk_marker >> "$TR"
mk_success_result >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "equal counts fires" "$OUT" "sub-pattern 12C"
assert_exit "equal counts exit 0" "$RC" "0"

# Test 9: Disabled via env → silent even with signature
reset_state
TR="$TMPDIR/t9.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_DISABLE=1 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable env silences" "$OUT" "sub-pattern 12C"
assert_exit "disable env exit 0" "$RC" "0"

# Test 10: Threshold raised to 2 with only 1 marker → silent
reset_state
TR="$TMPDIR/t10.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_THRESHOLD=2 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "threshold 2 with 1 marker silent" "$OUT" "sub-pattern 12C"
assert_exit "threshold 2 with 1 exit 0" "$RC" "0"

# Test 11: Explicit is_error=false counted as success
reset_state
TR="$TMPDIR/t11.jsonl"
mk_marker > "$TR"
mk_success_result_explicit >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "explicit is_error=false counted" "$OUT" "sub-pattern 12C"
assert_exit "explicit is_error=false exit 0" "$RC" "0"

# Test 12: is_error=true does NOT count as success
reset_state
TR="$TMPDIR/t12.jsonl"
mk_marker > "$TR"
mk_failed_result >> "$TR"
mk_failed_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "is_error=true not counted" "$OUT" "sub-pattern 12C"
assert_exit "is_error=true exit 0" "$RC" "0"

# Test 13: Top-level (non-.message) shape detected
reset_state
TR="$TMPDIR/t13.jsonl"
mk_marker > "$TR"
mk_success_result_top >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "top-level shape detected" "$OUT" "sub-pattern 12C"
assert_exit "top-level shape exit 0" "$RC" "0"

# Test 14: Cooldown — second call within cooldown stays silent
reset_state
TR="$TMPDIR/t14.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
OUT1=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
OUT2=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "first call fires" "$OUT1" "sub-pattern 12C"
assert_not_contains "second call within cooldown silent" "$OUT2" "sub-pattern 12C"

# Test 15: Cooldown — past cooldown refires
reset_state
TR="$TMPDIR/t15.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
OUT1=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_COOLDOWN=2 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
# Two no-op calls advance the counter (force silent via high threshold)
mk_input "$TR" | CC_SPURIOUS_MALFORMED_COOLDOWN=2 CC_SPURIOUS_MALFORMED_THRESHOLD=999 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>/dev/null
mk_input "$TR" | CC_SPURIOUS_MALFORMED_COOLDOWN=2 CC_SPURIOUS_MALFORMED_THRESHOLD=999 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>/dev/null
OUT2=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_COOLDOWN=2 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "first call fires" "$OUT1" "sub-pattern 12C"
assert_contains "third call past cooldown refires" "$OUT2" "sub-pattern 12C"

# Test 16: Different sessions have independent state
reset_state
TR="$TMPDIR/t16.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
OUT_A=$(mk_input "$TR" "session-A" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
OUT_B=$(mk_input "$TR" "session-B" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "session A fires" "$OUT_A" "sub-pattern 12C"
assert_contains "session B fires independently" "$OUT_B" "sub-pattern 12C"

# Test 17: Lookback window excludes earlier markers
reset_state
TR="$TMPDIR/t17.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
for i in $(seq 1 50); do
    mk_plain >> "$TR"
done
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_LOOKBACK=10 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "lookback excludes old signature" "$OUT" "sub-pattern 12C"
assert_exit "lookback exclude exit 0" "$RC" "0"

# Test 18: Lookback window includes recent signature
reset_state
TR="$TMPDIR/t18.jsonl"
for i in $(seq 1 5); do
    mk_plain >> "$TR"
done
mk_marker >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_LOOKBACK=5 CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "lookback includes recent" "$OUT" "sub-pattern 12C"
assert_exit "lookback include exit 0" "$RC" "0"

# Test 19: Non-JSON lines tolerated; signature still detected
reset_state
TR="$TMPDIR/t19.jsonl"
echo "garbage line not json" > "$TR"
mk_marker >> "$TR"
echo "more garbage" >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "non-json lines tolerated" "$OUT" "sub-pattern 12C"
assert_exit "non-json tolerated exit 0" "$RC" "0"

# Test 20: Mixed successful and failed results — only successes count
reset_state
TR="$TMPDIR/t20.jsonl"
mk_marker > "$TR"
mk_marker >> "$TR"
mk_success_result >> "$TR"
mk_failed_result >> "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "mixed results fires (2 success >= 2 markers)" "$OUT" "sub-pattern 12C"
assert_contains "shows accurate success count" "$OUT" "2 successful"
assert_exit "mixed results exit 0" "$RC" "0"

# Test 21: Plain assistant turns without tool_result blocks ignored
reset_state
TR="$TMPDIR/t21.jsonl"
mk_marker > "$TR"
mk_plain >> "$TR"
mk_plain >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "marker + plain assistant silent" "$OUT" "sub-pattern 12C"
assert_exit "marker + plain assistant exit 0" "$RC" "0"

# Test 22: Advisory explains verification path
reset_state
TR="$TMPDIR/t22.jsonl"
mk_marker > "$TR"
mk_success_result >> "$TR"
OUT=$(mk_input "$TR" | CC_SPURIOUS_MALFORMED_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "advisory mentions verification path" "$OUT" "Verify"
assert_contains "advisory mentions continue workaround" "$OUT" "continue"

echo ""
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
