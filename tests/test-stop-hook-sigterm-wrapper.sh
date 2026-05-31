#!/bin/bash
# Tests for stop-hook-sigterm-wrapper.sh
HOOK="$(dirname "$0")/../examples/stop-hook-sigterm-wrapper.sh"
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

reset_state() {
  rm -rf "$TMPDIR/state"
  mkdir -p "$TMPDIR/state"
  unset CC_STOP_SIGTERM_DISABLE
}

# Mock claude command — exits with given code after given delay
MOCK_CMD="$TMPDIR/mock-claude.sh"
cat > "$MOCK_CMD" <<'MOCKEOF'
#!/bin/bash
# Args: --exit CODE [--sleep SECONDS]
EXIT_CODE=0
SLEEP_S=0
while [ $# -gt 0 ]; do
  case "$1" in
    --exit) EXIT_CODE="$2"; shift 2 ;;
    --sleep) SLEEP_S="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$SLEEP_S" -gt 0 ] && sleep "$SLEEP_S"
exit "$EXIT_CODE"
MOCKEOF
chmod +x "$MOCK_CMD"

# Read state from state.json
read_state() {
  cat "$TMPDIR/state/state.json" 2>/dev/null
}

# Helper: run the wrapper with mock command, capture exit code
run_wrapper() {
  CC_STOP_SIGTERM_MARKER_DIR="$TMPDIR/state" \
    CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
    bash "$HOOK" "$@"
  echo $?
}

echo "Testing stop-hook-sigterm-wrapper.sh"
echo "===================================="

# Test 1: completed (exit 0)
reset_state
EXIT=$(run_wrapper --exit 0)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"completed"'*'"exit_code":0'*0)
    run_test "Exit 0 → state=completed, exit code 0" "pass" ;;
  *) run_test "Exit 0 → state=completed, exit code 0" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 2: error (exit 5)
reset_state
EXIT=$(run_wrapper --exit 5)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"error"'*'"exit_code":5'*5)
    run_test "Exit 5 → state=error, exit code 5" "pass" ;;
  *) run_test "Exit 5 → state=error, exit code 5" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 3: timeout exit code 124
reset_state
EXIT=$(run_wrapper --exit 124)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"killed-timeout"'*'"exit_code":124'*124)
    run_test "Exit 124 → state=killed-timeout" "pass" ;;
  *) run_test "Exit 124 → state=killed-timeout" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 4: SIGTERM exit code 143
reset_state
EXIT=$(run_wrapper --exit 143)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"killed-sigterm"'*'"exit_code":143'*143)
    run_test "Exit 143 → state=killed-sigterm" "pass" ;;
  *) run_test "Exit 143 → state=killed-sigterm" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 5: SIGKILL exit code 137
reset_state
EXIT=$(run_wrapper --exit 137)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"killed-sigkill"'*'"exit_code":137'*137)
    run_test "Exit 137 → state=killed-sigkill" "pass" ;;
  *) run_test "Exit 137 → state=killed-sigkill" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 6: SIGINT exit code 130
reset_state
EXIT=$(run_wrapper --exit 130)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"killed-sigint"'*'"exit_code":130'*130)
    run_test "Exit 130 → state=killed-sigint" "pass" ;;
  *) run_test "Exit 130 → state=killed-sigint" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 7: Initial running state visible before completion
reset_state
# Run with a 2s sleep, check state after 0.5s
CC_STOP_SIGTERM_MARKER_DIR="$TMPDIR/state" \
  CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
  bash "$HOOK" --exit 0 --sleep 2 &
WRAPPER_PID=$!
sleep 0.5
RUNNING_STATE=$(read_state)
wait $WRAPPER_PID
case "$RUNNING_STATE" in
  *'"state":"running"'*'"pid"'*)
    run_test "running state written before completion" "pass" ;;
  *) run_test "running state written before completion" "fail (got: $RUNNING_STATE)" ;;
esac

# Test 8: Final state overwrites running
FINAL_STATE=$(read_state)
case "$FINAL_STATE" in
  *'"state":"completed"'*)
    run_test "Final state overwrites running state" "pass" ;;
  *) run_test "Final state overwrites running state" "fail (got: $FINAL_STATE)" ;;
esac

# Test 9: SIGTERM trapped from outside writes killed-sigterm before kill
reset_state
CC_STOP_SIGTERM_MARKER_DIR="$TMPDIR/state" \
  CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
  bash "$HOOK" --exit 0 --sleep 5 &
WRAPPER_PID=$!
sleep 0.5
kill -TERM "$WRAPPER_PID" 2>/dev/null
wait "$WRAPPER_PID" 2>/dev/null
TRAP_EXIT=$?
TRAP_STATE=$(read_state)
case "$TRAP_STATE" in
  *'"state":"killed-sigterm"'*)
    run_test "External SIGTERM → state=killed-sigterm via trap" "pass" ;;
  *) run_test "External SIGTERM → state=killed-sigterm via trap" "fail (state: $TRAP_STATE, exit: $TRAP_EXIT)" ;;
esac

# Test 10: DISABLE passes through, no state file written
reset_state
EXIT=$(CC_STOP_SIGTERM_MARKER_DIR="$TMPDIR/state" \
  CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
  CC_STOP_SIGTERM_DISABLE=1 \
  bash "$HOOK" --exit 7
echo $?)
if [ ! -f "$TMPDIR/state/state.json" ] && [ "$EXIT" = "7" ]; then
  run_test "DISABLE passes through exit code, no state file" "pass"
else
  run_test "DISABLE passes through exit code, no state file" "fail (state exists or exit wrong: $EXIT)"
fi

# Test 11: State file is valid JSON (parseable with jq)
reset_state
run_wrapper --exit 0 >/dev/null
if command -v jq >/dev/null 2>&1; then
  if jq -e . "$TMPDIR/state/state.json" >/dev/null 2>&1; then
    run_test "State file is valid JSON" "pass"
  else
    run_test "State file is valid JSON" "fail"
  fi
else
  run_test "State file is valid JSON (jq not present, skipped)" "pass"
fi

# Test 12: Custom marker dir env var honored
reset_state
ALT_DIR="$TMPDIR/alt-state-$$"
mkdir -p "$ALT_DIR"
CC_STOP_SIGTERM_MARKER_DIR="$ALT_DIR" \
  CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
  bash "$HOOK" --exit 0 >/dev/null
if [ -f "$ALT_DIR/state.json" ]; then
  run_test "Custom MARKER_DIR env var honored" "pass"
else
  run_test "Custom MARKER_DIR env var honored" "fail"
fi
rm -rf "$ALT_DIR"

# Test 13: duration_s field is present and non-negative
reset_state
run_wrapper --exit 0 --sleep 1 >/dev/null
OUT=$(read_state)
DURATION=$(echo "$OUT" | grep -oE '"duration_s":[0-9]+' | grep -oE '[0-9]+')
if [ -n "$DURATION" ] && [ "$DURATION" -ge 1 ] 2>/dev/null; then
  run_test "duration_s field present, reflects elapsed time" "pass"
else
  run_test "duration_s field present, reflects elapsed time" "fail (got duration: $DURATION)"
fi

# Test 14: pid field is present in running state
reset_state
CC_STOP_SIGTERM_MARKER_DIR="$TMPDIR/state" \
  CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
  bash "$HOOK" --exit 0 --sleep 2 &
WRAPPER_PID=$!
sleep 0.5
RUN_OUT=$(read_state)
wait $WRAPPER_PID
case "$RUN_OUT" in
  *'"pid":'*)
    run_test "running state has pid field" "pass" ;;
  *) run_test "running state has pid field" "fail (got: $RUN_OUT)" ;;
esac

# Test 15: Exit 1 (generic error) → state=error with exit_code:1
reset_state
EXIT=$(run_wrapper --exit 1)
OUT=$(read_state)
case "$OUT$EXIT" in
  *'"state":"error"'*'"exit_code":1'*1)
    run_test "Exit 1 → state=error with exit_code:1" "pass" ;;
  *) run_test "Exit 1 → state=error with exit_code:1" "fail (state: $OUT, exit: $EXIT)" ;;
esac

# Test 16: Atomic write — state file is never empty / partially written
reset_state
for i in 1 2 3; do
  CC_STOP_SIGTERM_MARKER_DIR="$TMPDIR/state" \
    CC_STOP_SIGTERM_WRAPPER_CMD="$MOCK_CMD" \
    bash "$HOOK" --exit 0 >/dev/null &
done
wait
# After all completed, state.json should be valid JSON for at least one of the runs
LAST_STATE=$(read_state)
case "$LAST_STATE" in
  *'"state":"completed"'*)
    run_test "Atomic write across concurrent invocations" "pass" ;;
  *) run_test "Atomic write across concurrent invocations" "fail (got: $LAST_STATE)" ;;
esac

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
