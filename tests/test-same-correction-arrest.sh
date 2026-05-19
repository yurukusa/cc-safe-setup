#!/bin/bash
# Tests for same-correction-arrest.sh
#
# Verifies the hook behavior from issue #60506:
#   - Increments counter on correction-pattern messages.
#   - Emits warning while under threshold.
#   - Emits hard arrest reminder at threshold.
#   - Re-emits arrest reminder on every subsequent message until plan exists.
#   - Clears arrest when plan file is created.
#   - Ignores non-correction messages.

set -uo pipefail

HOOK="$(dirname "$0")/../examples/same-correction-arrest.sh"
PASS=0
FAIL=0
STATE_DIR="/tmp/cc-correction-arrest-test-$$"
PLAN_DIR="/tmp/cc-correction-arrest-test-$$/plans"
SESSION_ID="test-$$"
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"
ARREST_FILE="$STATE_DIR/${SESSION_ID}.arrested"

setup() {
    rm -rf "$STATE_DIR" 2>/dev/null || true
    mkdir -p "$STATE_DIR" "$PLAN_DIR"
}

run_hook() {
    local msg="$1"
    local threshold="${2:-3}"
    local input
    input=$(jq -nc \
        --arg sid "$SESSION_ID" \
        --arg msg "$msg" \
        '{session_id: $sid, prompt: $msg}')
    printf '%s' "$input" \
        | CC_CORRECTION_ARREST_THRESHOLD="$threshold" \
          CC_CORRECTION_ARREST_STATE_DIR="$STATE_DIR" \
          CC_CORRECTION_ARREST_PLAN_DIR="$PLAN_DIR" \
          bash "$HOOK" 2>&1 || true
}

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== same-correction-arrest.sh tests ==="

# --- Test 1: non-correction message is ignored ---
setup
output=$(run_hook "let's add a new feature" 3)
count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
if [ "$count" = "0" ] && ! echo "$output" | grep -q "Correction pattern"; then
    assert_pass "non-correction message does not increment or warn"
else
    assert_fail "non-correction should be a no-op (count=$count, output=$output)"
fi

# --- Test 2: correction message increments counter ---
setup
run_hook "we are going backwards" 3 >/dev/null
count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
if [ "$count" = "1" ]; then
    assert_pass "first correction increments counter to 1"
else
    assert_fail "expected count=1, got count=$count"
fi

# --- Test 3: pre-threshold warning shown ---
setup
output=$(run_hook "we are going backwards" 3)
if echo "$output" | grep -q "Correction pattern detected (1 of 3"; then
    assert_pass "pre-threshold warning identifies count and threshold"
else
    assert_fail "expected pre-threshold warning, got: $output"
fi

# --- Test 4: arrest fires at threshold ---
setup
run_hook "going backwards" 3 >/dev/null
run_hook "same mistake again" 3 >/dev/null
output=$(run_hook "i told you to stop doing this" 3)
if echo "$output" | grep -q "DRIFT ARREST" && [ -f "$ARREST_FILE" ]; then
    assert_pass "third correction fires arrest and writes marker"
else
    assert_fail "expected DRIFT ARREST + marker file (output=$output, marker=$([ -f "$ARREST_FILE" ] && echo yes || echo no))"
fi

# --- Test 5: arrest reminder persists on subsequent messages ---
setup
run_hook "going backwards" 1 >/dev/null   # threshold=1 → arrest immediately
output=$(run_hook "any unrelated follow-up message" 1)
if echo "$output" | grep -q "DRIFT ARREST STILL ACTIVE"; then
    assert_pass "arrest reminder re-emitted on next message until plan exists"
else
    assert_fail "expected persistent arrest reminder, got: $output"
fi

# --- Test 6: arrest clears when plan file is written ---
setup
run_hook "going backwards" 1 >/dev/null   # arrest
# Write the plan file
mkdir -p "$PLAN_DIR"
echo "# Drift arrest plan" > "$PLAN_DIR/drift-arrest-$SESSION_ID.md"
output=$(run_hook "ok, plan written, continuing" 1)
if echo "$output" | grep -q "Drift arrest cleared" && [ ! -f "$ARREST_FILE" ]; then
    assert_pass "arrest cleared by presence of plan file"
else
    assert_fail "expected arrest cleared, got output=$output marker_exists=$([ -f "$ARREST_FILE" ] && echo yes || echo no)"
fi

# --- Test 7: arrest references issue numbers in reminder ---
setup
output=$(run_hook "stop doing the same mistake going backwards" 1)
if echo "$output" | grep -q "#60506" && echo "$output" | grep -q "#60226"; then
    assert_pass "arrest reminder cites #60506 and #60226 for grounding"
else
    assert_fail "expected references to #60506 and #60226 (got: $output)"
fi

# --- Test 8: missing user message is a silent no-op ---
setup
input='{"session_id":"'"$SESSION_ID"'"}'
output=$(printf '%s' "$input" \
    | CC_CORRECTION_ARREST_STATE_DIR="$STATE_DIR" \
      CC_CORRECTION_ARREST_PLAN_DIR="$PLAN_DIR" \
      bash "$HOOK" 2>&1 || true)
count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
if [ "$count" = "0" ] && [ -z "$output" ]; then
    assert_pass "missing user message is a silent no-op"
else
    assert_fail "expected silent no-op, got count=$count output=$output"
fi

# --- Test 9: missing session_id uses default and still works ---
setup
input='{"prompt":"going backwards"}'
output=$(printf '%s' "$input" \
    | CC_CORRECTION_ARREST_THRESHOLD=1 \
      CC_CORRECTION_ARREST_STATE_DIR="$STATE_DIR" \
      CC_CORRECTION_ARREST_PLAN_DIR="$PLAN_DIR" \
      bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "DRIFT ARREST"; then
    assert_pass "missing session_id falls back to default session"
else
    assert_fail "expected DRIFT ARREST with default session, got: $output"
fi

# --- Test 10: counter resets between fresh state dirs (session isolation) ---
setup
run_hook "going backwards" 3 >/dev/null
count_a=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
setup   # wipe state
count_b=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
if [ "$count_a" = "1" ] && [ "$count_b" = "0" ]; then
    assert_pass "state is per-state-dir (isolation works)"
else
    assert_fail "expected count_a=1, count_b=0 (got $count_a, $count_b)"
fi

# Cleanup
rm -rf "$STATE_DIR" 2>/dev/null || true

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
