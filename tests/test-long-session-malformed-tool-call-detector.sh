#!/bin/bash
# Tests for long-session-malformed-tool-call-detector.sh
HOOK="examples/long-session-malformed-tool-call-detector.sh"
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

# Test 1: No transcript path → silent pass
reset_state
OUT=$(echo '{}' | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no transcript silent" "$OUT" "malformed"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Transcript exists but no marker → silent pass
reset_state
TR="$TMPDIR/t2.jsonl"
echo '{"message":{"role":"assistant","content":"hello world"}}' > "$TR"
OUT=$(mk_input "$TR" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no marker silent" "$OUT" "sub-pattern 12A"
assert_exit "no marker exit 0" "$RC" "0"

# Test 3: One marker occurrence → advisory fires
reset_state
TR="$TMPDIR/t3.jsonl"
echo '{"message":{"role":"system","content":"malformed and could not be parsed"}}' > "$TR"
OUT=$(mk_input "$TR" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "one marker fires advisory" "$OUT" "sub-pattern 12A"
assert_contains "advisory cites #62344" "$OUT" "#62344"
assert_contains "advisory cites #62123" "$OUT" "#62123"
assert_contains "advisory cites /clear recovery" "$OUT" "/clear"
assert_contains "advisory cites cluster tracker" "$OUT" "cluster-tracker"
assert_exit "one marker exit 0" "$RC" "0"

# Test 4: Multiple marker occurrences → advisory fires with count
reset_state
TR="$TMPDIR/t4.jsonl"
for i in 1 2 3 4; do
    echo "{\"turn\":$i,\"content\":\"malformed and could not be parsed\"}" >> "$TR"
done
OUT=$(mk_input "$TR" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "four markers fire advisory" "$OUT" "sub-pattern 12A"
assert_contains "advisory shows occurrence count" "$OUT" "4 occurrence"
assert_exit "four markers exit 0" "$RC" "0"

# Test 5: Disabled via env → silent even with marker
reset_state
TR="$TMPDIR/t5.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
OUT=$(mk_input "$TR" | CC_MALFORMED_DETECTOR_DISABLE=1 CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable env silences" "$OUT" "sub-pattern 12A"
assert_exit "disable env exit 0" "$RC" "0"

# Test 6: Threshold raised → one marker below threshold silent
reset_state
TR="$TMPDIR/t6.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
OUT=$(mk_input "$TR" | CC_MALFORMED_DETECTOR_THRESHOLD=2 CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "threshold 2 with 1 silent" "$OUT" "sub-pattern 12A"
assert_exit "threshold 2 with 1 exit 0" "$RC" "0"

# Test 7: Threshold raised, met → advisory fires
reset_state
TR="$TMPDIR/t7.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
echo '{"content":"malformed and could not be parsed"}' >> "$TR"
OUT=$(mk_input "$TR" | CC_MALFORMED_DETECTOR_THRESHOLD=2 CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "threshold 2 with 2 fires" "$OUT" "sub-pattern 12A"
assert_exit "threshold 2 with 2 exit 0" "$RC" "0"

# Test 8: Cooldown silences repeat within cooldown window
reset_state
TR="$TMPDIR/t8.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
# First call fires
OUT=$(mk_input "$TR" "sess8" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "cooldown first call fires" "$OUT" "sub-pattern 12A"
# Second call within cooldown should be silent (cooldown defaults to 50)
OUT2=$(mk_input "$TR" "sess8" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC2=$?
assert_not_contains "cooldown second call silent" "$OUT2" "sub-pattern 12A"
assert_exit "cooldown second call exit 0" "$RC2" "0"

# Test 9: Cooldown expired after enough tool calls → fires again
reset_state
TR="$TMPDIR/t9.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
# First call fires with default cooldown
mk_input "$TR" "sess9" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" >/dev/null 2>&1
# With cooldown 3, the call where SINCE >= 3 should refire. Track any refire across the loop.
REFIRED=0
LAST_RC=0
for _ in 1 2 3 4 5; do
    OUT_LOOP=$(mk_input "$TR" "sess9" | CC_MALFORMED_DETECTOR_COOLDOWN=3 CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
    LAST_RC=$?
    if echo "$OUT_LOOP" | grep -q "sub-pattern 12A"; then REFIRED=1; fi
done
if [ "$REFIRED" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: cooldown expired refires (no refire detected across 5 calls)"; fi
assert_exit "cooldown expired exit 0" "$LAST_RC" "0"

# Test 10: Different sessions track independently
reset_state
TR="$TMPDIR/t10.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
# Session A fires once
OUT_A=$(mk_input "$TR" "session-A" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "session A fires" "$OUT_A" "sub-pattern 12A"
# Session B is a fresh session and should fire independently
OUT_B=$(mk_input "$TR" "session-B" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "session B fires independently" "$OUT_B" "sub-pattern 12A"

# Test 11: Lookback window respected — marker outside window not detected
reset_state
TR="$TMPDIR/t11.jsonl"
# Marker on line 1
echo '{"content":"malformed and could not be parsed"}' > "$TR"
# 50 noise lines after
for i in $(seq 1 50); do echo "{\"line\":$i,\"content\":\"normal output\"}" >> "$TR"; done
# Lookback 10 → marker outside window
OUT=$(mk_input "$TR" "sess11" | CC_MALFORMED_DETECTOR_LOOKBACK=10 CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "lookback 10 misses far marker" "$OUT" "sub-pattern 12A"
assert_exit "lookback 10 exit 0" "$RC" "0"

# Test 12: Lookback 100 catches marker on line 1 with 50 noise lines after
reset_state
TR="$TMPDIR/t12.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
for i in $(seq 1 50); do echo "{\"line\":$i,\"content\":\"normal output\"}" >> "$TR"; done
OUT=$(mk_input "$TR" "sess12" | CC_MALFORMED_DETECTOR_LOOKBACK=100 CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "lookback 100 catches early marker" "$OUT" "sub-pattern 12A"
assert_exit "lookback 100 exit 0" "$RC" "0"

# Test 13: Transcript path override via env (no JSON parsing needed)
reset_state
TR="$TMPDIR/t13.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
OUT=$(echo '{}' | CC_MALFORMED_DETECTOR_TRANSCRIPT="$TR" CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "transcript env override works" "$OUT" "sub-pattern 12A"
assert_exit "transcript env override exit 0" "$RC" "0"

# Test 14: Nonexistent transcript path → silent
reset_state
OUT=$(mk_input "/nonexistent/path.jsonl" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "nonexistent path silent" "$OUT" "sub-pattern 12A"
assert_exit "nonexistent path exit 0" "$RC" "0"

# Test 15: Empty stdin → silent (graceful handling)
reset_state
OUT=$(printf '' | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "empty stdin silent" "$OUT" "sub-pattern 12A"
assert_exit "empty stdin exit 0" "$RC" "0"

# Test 16: Session id with special characters is sanitized safely
reset_state
TR="$TMPDIR/t16.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
OUT=$(mk_input "$TR" "session/with\\nasty:chars*" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "sanitized session id works" "$OUT" "sub-pattern 12A"
assert_exit "sanitized session id exit 0" "$RC" "0"

# Test 17: Advisory cites the recovery trade-off (context loss)
reset_state
TR="$TMPDIR/t17.jsonl"
echo '{"content":"malformed and could not be parsed"}' > "$TR"
OUT=$(mk_input "$TR" "sess17" | CC_MALFORMED_DETECTOR_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "advisory cites context loss trade-off" "$OUT" "discards"
assert_contains "advisory cites checkpoint suggestion" "$OUT" "checkpoint"

echo ""
echo "================================"
echo "PASS: $PASS  FAIL: $FAIL"
echo "================================"
exit $FAIL
