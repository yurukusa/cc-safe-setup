#!/bin/bash
# Tests for auth-status-checker.sh
HOOK="$(dirname "$0")/../examples/auth-status-checker.sh"
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
  unset CC_AUTH_STATUS_CHECKER_REMIND
  unset CC_AUTH_STATUS_CHECKER_DISABLE
  unset CC_AUTH_STATUS_CHECKER_QUIET
}

echo "Testing auth-status-checker.sh"
echo "==============================="

# Test 1: Default (no env vars) → silent
reset_env
OUT=$(bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Default (no env vars) is silent" pass
else
  run_test "Default (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: REMIND=1 → emits advisory
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "auth-status-checker"; then
  run_test "REMIND=1 emits the advisory" pass
else
  run_test "REMIND=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: REMIND=1 + DISABLE=1 → silent (DISABLE wins)
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 CC_AUTH_STATUS_CHECKER_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=1 + DISABLE=1 silent (DISABLE wins)" pass
else
  run_test "REMIND+DISABLE (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: REMIND=1 + QUIET=1 → silent (QUIET wins)
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 CC_AUTH_STATUS_CHECKER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=1 + QUIET=1 silent (QUIET wins)" pass
else
  run_test "REMIND+QUIET (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: REMIND empty string → silent
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND="" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND='' is silent (not '1')" pass
else
  run_test "REMIND='' (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: REMIND=0 → silent
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=0 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=0 is silent" pass
else
  run_test "REMIND=0 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: Advisory cites all seven sub-cluster axes
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
H19A=$(printf '%s' "$OUT" | grep -c "19A")
H19B=$(printf '%s' "$OUT" | grep -c "19B")
H19C=$(printf '%s' "$OUT" | grep -c "19C")
H19D=$(printf '%s' "$OUT" | grep -c "19D")
H19E=$(printf '%s' "$OUT" | grep -c "19E")
H19F=$(printf '%s' "$OUT" | grep -c "19F")
H19G=$(printf '%s' "$OUT" | grep -c "19G")
if [ "$H19A" -ge "1" ] && [ "$H19B" -ge "1" ] && [ "$H19C" -ge "1" ] && [ "$H19D" -ge "1" ] && [ "$H19E" -ge "1" ] && [ "$H19F" -ge "1" ] && [ "$H19G" -ge "1" ]; then
  run_test "Advisory cites all seven sub-cluster axes (19A-19G)" pass
else
  run_test "Seven axes (a=$H19A b=$H19B c=$H19C d=$H19D e=$H19E f=$H19F g=$H19G)" fail
fi

# Test 8: Advisory contains all five mitigation paths
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
HAS1=$(printf '%s' "$OUT" | grep -c "1) Periodic")
HAS2=$(printf '%s' "$OUT" | grep -c "2) Single-window")
HAS3=$(printf '%s' "$OUT" | grep -c "3) CLI preference")
HAS4=$(printf '%s' "$OUT" | grep -c "4) Daily re-auth")
HAS5=$(printf '%s' "$OUT" | grep -c "5) Scheduled reboot")
if [ "$HAS1" -ge "1" ] && [ "$HAS2" -ge "1" ] && [ "$HAS3" -ge "1" ] && [ "$HAS4" -ge "1" ] && [ "$HAS5" -ge "1" ]; then
  run_test "Advisory contains all five mitigation paths" pass
else
  run_test "Five mitigations (1=$HAS1 2=$HAS2 3=$HAS3 4=$HAS4 5=$HAS5)" fail
fi

# Test 9: Advisory cites the canonical fresh issue (#63919 from 2026-05-30)
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "63919"; then
  run_test "Advisory cites #63919 (2026-05-30 fresh)" pass
else
  run_test "Cites #63919 (out_len=${#OUT})" fail
fi

# Test 10: Advisory cites #62354 HIGH BLOCKER session expiry
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "62354"; then
  run_test "Advisory cites #62354 HIGH BLOCKER" pass
else
  run_test "Cites #62354 (out_len=${#OUT})" fail
fi

# Test 11: Advisory cites #63185 3P Bedrock SSO day-2+
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "63185"; then
  run_test "Advisory cites #63185 3P Bedrock SSO" pass
else
  run_test "Cites #63185 (out_len=${#OUT})" fail
fi

# Test 12: Advisory references the field guide gist
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "gist.github.com"; then
  run_test "Advisory references the field guide gist" pass
else
  run_test "Field guide link (out_len=${#OUT})" fail
fi

# Test 13: Advisory explains how to disable
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "unset CC_AUTH_STATUS_CHECKER_REMIND" \
   && printf '%s' "$OUT" | grep -q "export CC_AUTH_STATUS_CHECKER_QUIET=1"; then
  run_test "Advisory explains how to disable" pass
else
  run_test "Disable instructions (out_len=${#OUT})" fail
fi

# Test 14: Advisory uses candidate-cluster framing
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "candidate"; then
  run_test "Advisory uses candidate-cluster framing" pass
else
  run_test "Candidate framing (out_len=${#OUT})" fail
fi

# Test 15: Advisory has substantial content (>=2000 chars)
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if [ "${#OUT}" -ge "2000" ]; then
  run_test "Advisory has substantial content (>=2000 chars)" pass
else
  run_test "Advisory size (chars=${#OUT})" fail
fi

# Test 16: Never blocks — exit 0 when emitting
reset_env
CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when emitting)" pass
else
  run_test "Exit on emit (exit=$EXIT)" fail
fi

# Test 17: Never blocks — exit 0 when silent
reset_env
bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when silent)" pass
else
  run_test "Exit when silent (exit=$EXIT)" fail
fi

# Test 18: Handles no-stdin gracefully (SessionStart pattern)
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" < /dev/null 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "auth-status-checker"; then
  run_test "Handles no-stdin gracefully" pass
else
  run_test "No-stdin (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 19: Advisory references the unifying root mechanism
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "silently lapsed\|silently lapse"; then
  run_test "Advisory articulates the silent-lapse root mechanism" pass
else
  run_test "Silent lapse framing (out_len=${#OUT})" fail
fi

# Test 20: Advisory cites the cluster-tracker promotion criteria
reset_env
OUT=$(CC_AUTH_STATUS_CHECKER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "cluster-tracker"; then
  run_test "Advisory references cluster-tracker page" pass
else
  run_test "Cluster-tracker reference (out_len=${#OUT})" fail
fi

echo "==============================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
