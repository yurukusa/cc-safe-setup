#!/bin/bash
# Tests for goal-loop-detector.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/goal-loop-detector.sh"
STATE_FILE="${HOME}/.claude/state/goal-loop-detector.json"
TEST_STATE_DIR="$(mktemp -d)"
TRANSCRIPT="${TEST_STATE_DIR}/transcript.jsonl"
PASS=0; FAIL=0; TOTAL=0

# Override HOME to isolate state during tests
export HOME="$TEST_STATE_DIR"
export CC_GOAL_LOOP_N=5
export CC_GOAL_LOOP_MAX_LEN=500

make_transcript() {
    local text="$1"
    cat > "$TRANSCRIPT" <<EOF
{"role": "user", "content": "test"}
{"role": "assistant", "content": "$text"}
EOF
}

make_payload() {
    local sid="$1"
    jq -nc --arg sid "$sid" --arg path "$TRANSCRIPT" '{
        session_id: $sid,
        transcript_path: $path
    }'
}

reset_state() {
    rm -rf "${TEST_STATE_DIR}/.claude"
}

run_exit_zero() {
    local desc="$1"; local sid="$2"; local text="$3"
    TOTAL=$((TOTAL + 1))
    make_transcript "$text"
    local payload
    payload=$(make_payload "$sid")
    local out
    out=$(echo "$payload" | bash "$HOOK" 2>&1)
    local code=$?
    if [[ "$code" -eq 0 ]]; then
        PASS=$((PASS + 1))
        echo "✅ $desc (exit 0)"
    else
        FAIL=$((FAIL + 1))
        echo "❌ $desc (exit $code, expected 0): $out"
    fi
}

run_exit_two() {
    local desc="$1"; local sid="$2"; local text="$3"
    TOTAL=$((TOTAL + 1))
    make_transcript "$text"
    local payload
    payload=$(make_payload "$sid")
    local out
    out=$(echo "$payload" | bash "$HOOK" 2>&1)
    local code=$?
    if [[ "$code" -eq 2 ]]; then
        PASS=$((PASS + 1))
        echo "✅ $desc (exit 2 = block)"
    else
        FAIL=$((FAIL + 1))
        echo "❌ $desc (exit $code, expected 2): $out"
    fi
}

# --- TESTS ---

echo "=== Test 1: First short identical message → exit 0 ==="
reset_state
run_exit_zero "first 'condition not satisfied' → no block" \
    "session-1" "condition not satisfied"

echo ""
echo "=== Test 2: Identical short messages, less than N → exit 0 ==="
reset_state
for i in 1 2 3 4; do
    run_exit_zero "$i identical messages (< N=5) → no block" \
        "session-2" "condition not satisfied"
done

echo ""
echo "=== Test 3: N identical short messages → exit 2 ==="
reset_state
for i in 1 2 3 4; do
    run_exit_zero "build-up message $i" \
        "session-3" "condition not satisfied"
done
run_exit_two "5th identical message → BLOCK" \
    "session-3" "condition not satisfied"

echo ""
echo "=== Test 4: After block, state resets → next message exit 0 ==="
# State was reset inside hook on exit 2
run_exit_zero "first message after block → no block (fresh state)" \
    "session-3" "condition not satisfied"

echo ""
echo "=== Test 5: Different messages, N times → exit 0 ==="
reset_state
run_exit_zero "msg A" "session-4" "condition not satisfied: missing X"
run_exit_zero "msg B" "session-4" "condition not satisfied: missing Y"
run_exit_zero "msg A again" "session-4" "condition not satisfied: missing X"
run_exit_zero "msg B again" "session-4" "condition not satisfied: missing Y"
run_exit_zero "msg A again" "session-4" "condition not satisfied: missing X"

echo ""
echo "=== Test 6: Long message resets state ==="
reset_state
for i in 1 2 3 4; do
    run_exit_zero "build-up $i" "session-5" "condition not satisfied"
done
# Long message (>500 chars) should reset state
LONG=$(printf 'a%.0s' {1..600})
run_exit_zero "long substantive message → reset" "session-5" "$LONG"
# Now identical short messages count from zero again
run_exit_zero "post-reset msg 1" "session-5" "condition not satisfied"
run_exit_zero "post-reset msg 2" "session-5" "condition not satisfied"
run_exit_zero "post-reset msg 3" "session-5" "condition not satisfied"
run_exit_zero "post-reset msg 4" "session-5" "condition not satisfied"
run_exit_two "post-reset msg 5 → BLOCK again" "session-5" "condition not satisfied"

echo ""
echo "=== Test 7: Independent sessions tracked separately ==="
reset_state
for i in 1 2 3 4; do
    run_exit_zero "sess-A msg $i" "session-A" "loop condition A"
done
# Different session should not be affected
run_exit_zero "sess-B msg 1 (independent)" "session-B" "loop condition B"
run_exit_two "sess-A msg 5 → BLOCK" "session-A" "loop condition A"
run_exit_zero "sess-B msg 2 (still independent)" "session-B" "loop condition B"

echo ""
echo "=== Test 8: CC_GOAL_LOOP_DISABLE=1 → exit 0 always ==="
reset_state
export CC_GOAL_LOOP_DISABLE=1
for i in 1 2 3 4 5 6 7; do
    run_exit_zero "disabled, msg $i" "session-6" "condition not satisfied"
done
unset CC_GOAL_LOOP_DISABLE

echo ""
echo "=== Test 9: Missing transcript → exit 0 (no-op) ==="
reset_state
# Make transcript path invalid
rm -f "$TRANSCRIPT"
TOTAL=$((TOTAL + 1))
payload=$(jq -nc '{
    session_id: "session-7",
    transcript_path: "/nonexistent/transcript.jsonl"
}')
out=$(echo "$payload" | bash "$HOOK" 2>&1)
code=$?
if [[ "$code" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "✅ missing transcript → exit 0"
else
    FAIL=$((FAIL + 1))
    echo "❌ missing transcript (exit $code): $out"
fi

echo ""
echo "=== Test 10: Empty/malformed payload → exit 0 ==="
TOTAL=$((TOTAL + 1))
out=$(echo "" | bash "$HOOK" 2>&1)
code=$?
if [[ "$code" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "✅ empty payload → exit 0"
else
    FAIL=$((FAIL + 1))
    echo "❌ empty payload (exit $code): $out"
fi

# --- SUMMARY ---
echo ""
echo "================================"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
echo "================================"

# Cleanup
rm -rf "$TEST_STATE_DIR"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
