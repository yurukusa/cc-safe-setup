#!/bin/bash
# Tests for parallel-batch-size-limiter.sh
HOOK="$(dirname "$0")/../examples/parallel-batch-size-limiter.sh"
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
  unset CC_PARALLEL_BATCH_LIMITER_DISABLE
  unset CC_PARALLEL_BATCH_LIMITER_QUIET
  unset CC_PARALLEL_BATCH_LIMITER_THRESHOLD
  unset CC_PARALLEL_BATCH_LIMITER_WINDOW_MS
}

# Fire the hook N times in quick succession (with optional THRESHOLD/WINDOW_MS)
fire_n_calls() {
  local n="$1"
  local last_out=""
  local last_exit=0
  for i in $(seq 1 "$n"); do
    last_out=$(printf '%s' '{"tool_input": {"command": "ls"}, "tool_name": "Bash"}' \
      | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" \
        ${CC_PARALLEL_BATCH_LIMITER_THRESHOLD:+CC_PARALLEL_BATCH_LIMITER_THRESHOLD="$CC_PARALLEL_BATCH_LIMITER_THRESHOLD"} \
        ${CC_PARALLEL_BATCH_LIMITER_WINDOW_MS:+CC_PARALLEL_BATCH_LIMITER_WINDOW_MS="$CC_PARALLEL_BATCH_LIMITER_WINDOW_MS"} \
        bash "$HOOK" 2>&1)
    last_exit=$?
  done
  echo "$last_out"
  return $last_exit
}

echo "Testing parallel-batch-size-limiter.sh"
echo "======================================"

# Test 1: DISABLE=1 silences
reset_state
OUT=$(for i in 1 2 3 4 5 6 7; do
  printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_DISABLE=1 bash "$HOOK" 2>&1
done)
if [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences across 7 fires" pass
else
  run_test "DISABLE=1 (out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 silences
reset_state
OUT=$(for i in 1 2 3 4 5 6 7; do
  printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_QUIET=1 bash "$HOOK" 2>&1
done)
if [ -z "$OUT" ]; then
  run_test "QUIET=1 silences" pass
else
  run_test "QUIET=1 (out_len=${#OUT})" fail
fi

# Test 3: Below threshold → silent
reset_state
OUT=$(for i in 1 2 3; do
  printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=6 bash "$HOOK" 2>&1
done)
if [ -z "$OUT" ]; then
  run_test "Below threshold (3 calls vs 6) → silent" pass
else
  run_test "Below threshold (out_len=${#OUT})" fail
fi

# Test 4: At threshold → warning
reset_state
LAST_OUT=""
for i in 1 2 3 4 5 6; do
  LAST_OUT=$(printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=6 bash "$HOOK" 2>&1)
done
if printf '%s' "$LAST_OUT" | grep -q "Large parallel batch detected"; then
  run_test "At threshold (6 calls) → warning emitted" pass
else
  run_test "At threshold (no warning text)" fail
fi

# Test 5: Above threshold → warning (single warning, not per-call)
reset_state
WARN_COUNT=0
for i in 1 2 3 4 5 6 7 8; do
  OUT=$(printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=6 bash "$HOOK" 2>&1)
  if printf '%s' "$OUT" | grep -q "Large parallel batch"; then
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
done
if [ "$WARN_COUNT" = "1" ]; then
  run_test "8 calls → exactly 1 warning (debounced)" pass
else
  run_test "Debounce (got $WARN_COUNT warnings, expected 1)" fail
fi

# Test 6: Empty input → silent, no crash
reset_state
OUT=$(printf '%s' "" | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Empty input → silent, no crash" pass
else
  run_test "Empty input (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: Malformed JSON → no crash
reset_state
OUT=$(printf '%s' "{not valid" | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Malformed JSON → no crash" pass
else
  run_test "Malformed JSON (exit=$EXIT)" fail
fi

# Test 8: Configurable threshold (THRESHOLD=3)
reset_state
LAST_OUT=""
for i in 1 2 3; do
  LAST_OUT=$(printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=3 bash "$HOOK" 2>&1)
done
if printf '%s' "$LAST_OUT" | grep -q "Large parallel batch"; then
  run_test "THRESHOLD=3 triggers at 3 calls" pass
else
  run_test "THRESHOLD=3 (no warning at 3)" fail
fi

# Test 9: Old events outside window are pruned (WINDOW_MS=100)
reset_state
# Generate 5 calls
for i in 1 2 3 4 5; do
  printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=10 CC_PARALLEL_BATCH_LIMITER_WINDOW_MS=100 bash "$HOOK" >/dev/null 2>&1
done
# Wait longer than window
sleep 0.3
# Need to also reset warn-file so debounce doesn't suppress
rm -f "$STATE/last-warn"
# New call should not trigger because old ones are pruned
OUT=$(printf '%s' '{"tool_input": {"command": "ls"}}' \
  | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=2 CC_PARALLEL_BATCH_LIMITER_WINDOW_MS=100 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Old events pruned (WINDOW_MS=100, sleep 0.3)" pass
else
  run_test "Pruning (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 10: After window expires, second batch can trigger fresh warning
reset_state
# First batch
for i in 1 2 3 4 5 6; do
  printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=6 CC_PARALLEL_BATCH_LIMITER_WINDOW_MS=100 bash "$HOOK" >/dev/null 2>&1
done
# Wait beyond window
sleep 0.3
# Second batch
LAST_OUT=""
for i in 1 2 3 4 5 6; do
  LAST_OUT=$(printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=6 CC_PARALLEL_BATCH_LIMITER_WINDOW_MS=100 bash "$HOOK" 2>&1)
done
if printf '%s' "$LAST_OUT" | grep -q "Large parallel batch"; then
  run_test "Second batch after window expires → fresh warning" pass
else
  run_test "Second batch (no warning emitted)" fail
fi

# Test 11: State dir auto-created
reset_state
rm -rf "$STATE"
OUT=$(printf '%s' '{"tool_input": {"command": "ls"}}' \
  | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE/nested/deep" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -d "$STATE/nested/deep" ]; then
  run_test "State dir auto-created (nested)" pass
else
  run_test "State dir creation (exit=$EXIT)" fail
fi

# Test 12: Hook does not block tool execution (exits 0 even on warning)
reset_state
LAST_EXIT=0
for i in 1 2 3 4 5 6; do
  printf '%s' '{"tool_input": {"command": "ls"}}' \
    | CC_PARALLEL_BATCH_LIMITER_STATE_DIR="$STATE" CC_PARALLEL_BATCH_LIMITER_THRESHOLD=6 bash "$HOOK" >/dev/null 2>&1
  LAST_EXIT=$?
done
if [ "$LAST_EXIT" = "0" ]; then
  run_test "Hook exits 0 even when warning fires (advisory only)" pass
else
  run_test "Hook exit code (got $LAST_EXIT, expected 0)" fail
fi

echo "======================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
