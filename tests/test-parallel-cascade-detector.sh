#!/bin/bash
# Tests for parallel-cascade-detector.sh
HOOK="$(dirname "$0")/../examples/parallel-cascade-detector.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
STATE="$TMPDIR/state"

reset_state() {
  rm -rf "$STATE"
  mkdir -p "$STATE"
  unset CC_PARALLEL_CASCADE_DISABLE
  unset CC_PARALLEL_CASCADE_QUIET
  unset CC_PARALLEL_CASCADE_THRESHOLD
  unset CC_PARALLEL_CASCADE_WINDOW_SEC
}

make_input() {
  local response="$1"
  jq -nR --arg r "$response" '{tool_response: $r}'
}

echo "Testing parallel-cascade-detector.sh"
echo "===================================="

# Test 1: DISABLE=1 silences entirely
reset_state
INPUT=$(make_input "Cancelled: parallel tool call Bash(git log) errored")
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences entirely" pass
else
  run_test "DISABLE=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 silences
reset_state
INPUT=$(make_input "Cancelled: parallel tool call Bash(curl) errored")
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences" pass
else
  run_test "QUIET=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: Non-cascade response → no warning
reset_state
INPUT=$(make_input "Read file successfully: 123 bytes")
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Non-cascade response → silent" pass
else
  run_test "Non-cascade (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: Single cascade event below threshold → silent
reset_state
INPUT=$(make_input "Cancelled: parallel tool call Bash(git log -1 bad-rev) errored")
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Single event below threshold → silent" pass
else
  run_test "Single event (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: Multiple events crossing threshold → warning
reset_state
INPUT=$(make_input "Cancelled: parallel tool call Bash(git) errored")
for i in 1 2 3 4 5; do
  printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" >/dev/null 2>&1
done
INPUT2=$(make_input "Cancelled: parallel tool call Bash(curl) errored")
OUT=$(printf '%s' "$INPUT2" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "Parallel-batch cascade detected"; then
  run_test "Multiple events → warning emitted" pass
else
  run_test "Multiple events warning (exit=$EXIT, no warning text)" fail
fi

# Test 6: Empty input → silent
reset_state
OUT=$(printf '%s' "" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Empty input → silent" pass
else
  run_test "Empty input (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: Malformed JSON → silent (no crash)
reset_state
OUT=$(printf '%s' "{not valid json" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Malformed JSON → no crash" pass
else
  run_test "Malformed JSON (exit=$EXIT)" fail
fi

# Test 8: Cascade message in nested tool_response.output
reset_state
INPUT=$(jq -n '{tool_response: {output: "Cancelled: parallel tool call Bash(pkill) errored"}}')
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
# Single event with default threshold of 5 → no warning, but no error
if [ "$EXIT" = "0" ]; then
  run_test "Nested tool_response.output handled" pass
else
  run_test "Nested response (exit=$EXIT)" fail
fi

# Test 9: Case-insensitive cancellation detection
reset_state
INPUT=$(make_input "CANCELLED: parallel tool call Bash(test) errored")
for i in 1 2 3 4 5; do
  printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" >/dev/null 2>&1
done
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "cascade detected"; then
  run_test "Case-insensitive cancellation detected" pass
else
  run_test "Case-insensitive (exit=$EXIT)" fail
fi

# Test 10: Configurable threshold (THRESHOLD=2)
reset_state
INPUT=$(make_input "Cancelled: parallel tool call Bash(git) errored")
printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=2 bash "$HOOK" >/dev/null 2>&1
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=2 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "cascade detected"; then
  run_test "THRESHOLD=2 triggers at 2 events" pass
else
  run_test "THRESHOLD=2 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 11: Old events outside window are pruned (WINDOW_SEC=1)
reset_state
INPUT=$(make_input "Cancelled: parallel tool call Bash(test) errored")
# Generate 5 events
for i in 1 2 3 4 5; do
  printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=10 bash "$HOOK" >/dev/null 2>&1
done
# Wait for window to expire
sleep 2
# New event should not trigger because old ones are pruned
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=2 CC_PARALLEL_CASCADE_WINDOW_SEC=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Old events pruned (WINDOW_SEC=1, sleep 2)" pass
else
  run_test "Pruning (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 12: tool_result field also works
reset_state
INPUT=$(jq -n '{tool_result: "Cancelled: parallel tool call Bash(rm) errored"}')
for i in 1 2 3 4 5; do
  printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" >/dev/null 2>&1
done
OUT=$(printf '%s' "$INPUT" | CC_PARALLEL_CASCADE_STATE_DIR="$STATE" CC_PARALLEL_CASCADE_THRESHOLD=5 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "cascade detected"; then
  run_test "tool_result fallback field works" pass
else
  run_test "tool_result fallback (exit=$EXIT)" fail
fi

echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
