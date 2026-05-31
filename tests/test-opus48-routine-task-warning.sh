#!/bin/bash
# Tests for opus48-routine-task-warning.sh
HOOK="$(dirname "$0")/../examples/opus48-routine-task-warning.sh"
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

reset_env() {
  unset CC_OPUS48_ROUTINE_WARN
  unset CC_OPUS48_ROUTINE_DISABLE
  unset CC_OPUS48_ROUTINE_QUIET
}

echo "Testing opus48-routine-task-warning.sh"
echo "======================================="

# Test 1: Default (no env vars) → silent
reset_env
OUT=$(bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Default (no env vars) is silent" pass
else
  run_test "Default (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: WARN=1 → emits advisory
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "opus48-routine-task-warning"; then
  run_test "WARN=1 emits the advisory" pass
else
  run_test "WARN=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: WARN=1 + DISABLE=1 → silent (DISABLE wins)
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 CC_OPUS48_ROUTINE_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "WARN=1 + DISABLE=1 silent (DISABLE wins)" pass
else
  run_test "WARN+DISABLE (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: WARN=1 + QUIET=1 → silent (QUIET wins)
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 CC_OPUS48_ROUTINE_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "WARN=1 + QUIET=1 silent (QUIET wins)" pass
else
  run_test "WARN+QUIET (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: WARN empty string → silent
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN="" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "WARN='' is silent (not '1')" pass
else
  run_test "WARN='' (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: WARN=0 → silent
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=0 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "WARN=0 is silent (not '1')" pass
else
  run_test "WARN=0 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: WARN=other value → silent (strict '1' check)
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=yes bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "WARN=yes is silent (strict '1' required)" pass
else
  run_test "WARN=yes (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 8: Advisory references #64153 anchor
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "#64153"; then
  run_test "Advisory references #64153 anchor" pass
else
  run_test "Advisory references #64153 (out: ${OUT:0:200})" fail
fi

# Test 9: Advisory names the three operator-side mitigations
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
M1=$(printf '%s' "$OUT" | grep -c "claude-opus-4-7" || true)
M2=$(printf '%s' "$OUT" | grep -c "effort=low" || true)
M3=$(printf '%s' "$OUT" | grep -c "jq" || true)
if [ "$M1" -ge 1 ] && [ "$M2" -ge 1 ] && [ "$M3" -ge 1 ]; then
  run_test "Advisory names all three mitigations (Opus 4.7 / effort=low / jq audit)" pass
else
  run_test "Mitigations (Opus 4.7=$M1, effort=low=$M2, jq=$M3)" fail
fi

# Test 10: Advisory mentions the companion hook
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "output-token-spike-detector"; then
  run_test "Advisory mentions companion hook output-token-spike-detector.sh" pass
else
  run_test "Companion hook reference (out: ${OUT:0:200})" fail
fi

# Test 11: Advisory cites the candidate-cluster framing
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "candidate"; then
  run_test "Advisory uses candidate-cluster framing" pass
else
  run_test "Candidate framing (out: ${OUT:0:200})" fail
fi

# Test 12: Advisory provides opt-out instructions
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "unset CC_OPUS48_ROUTINE_WARN"; then
  run_test "Advisory provides opt-out instructions" pass
else
  run_test "Opt-out instructions (out: ${OUT:0:200})" fail
fi

# Test 13: Advisory differentiates from Cluster 22 (fabrication)
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "Cluster 22"; then
  run_test "Advisory differentiates from Cluster 22 (fabrication)" pass
else
  run_test "Cluster 22 differentiation (out: ${OUT:0:200})" fail
fi

# Test 14: Advisory differentiates from Cluster 4 (Pro Max quota)
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "Cluster 4"; then
  run_test "Advisory differentiates from Cluster 4 (Pro Max quota)" pass
else
  run_test "Cluster 4 differentiation (out: ${OUT:0:200})" fail
fi

# Test 15: Advisory names all four sub-cluster axes (23A, 23B, 23C, 23D)
reset_env
OUT=$(CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>&1)
A=$(printf '%s' "$OUT" | grep -c "23A" || true)
B=$(printf '%s' "$OUT" | grep -c "23B" || true)
C=$(printf '%s' "$OUT" | grep -c "23C" || true)
D=$(printf '%s' "$OUT" | grep -c "23D" || true)
if [ "$A" -ge 1 ] && [ "$B" -ge 1 ] && [ "$C" -ge 1 ] && [ "$D" -ge 1 ]; then
  run_test "Advisory names all four sub-cluster axes (23A/B/C/D)" pass
else
  run_test "Sub-cluster axes (23A=$A, 23B=$B, 23C=$C, 23D=$D)" fail
fi

# Test 16: Hook never blocks (exit always 0 across all paths)
reset_env
bash "$HOOK" 2>/dev/null; E1=$?
CC_OPUS48_ROUTINE_WARN=1 bash "$HOOK" 2>/dev/null; E2=$?
CC_OPUS48_ROUTINE_DISABLE=1 bash "$HOOK" 2>/dev/null; E3=$?
CC_OPUS48_ROUTINE_QUIET=1 bash "$HOOK" 2>/dev/null; E4=$?
if [ "$E1" = "0" ] && [ "$E2" = "0" ] && [ "$E3" = "0" ] && [ "$E4" = "0" ]; then
  run_test "Hook never blocks (exit 0 across all paths)" pass
else
  run_test "Exit codes (default=$E1, WARN=$E2, DISABLE=$E3, QUIET=$E4)" fail
fi

# Test 17: Hook ignores stdin (does not consume payload)
reset_env
OUT=$(echo '{"session_id":"s1","model":"claude-opus-4-8"}' | bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Hook ignores stdin when not opted in" pass
else
  run_test "Stdin handling (exit=$EXIT, out_len=${#OUT})" fail
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
