#!/bin/bash
# Tests for sonnet-45-deprecation-helper.sh
HOOK="$(dirname "$0")/../examples/sonnet-45-deprecation-helper.sh"
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

echo "Testing sonnet-45-deprecation-helper.sh"
echo "========================================"

# Test 1: QUIET=1 always silences, regardless of other state
OUT=$(CC_SONNET_45_HELPER_QUIET=1 CC_SONNET_45_HELPER_REMIND=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences even with REMIND=1" pass
else
  run_test "QUIET=1 silences even with REMIND=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: ANTHROPIC_MODEL explicitly set to 4.5 → silent
OUT=$(unset CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-sonnet-4-5-20250929 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL=4.5 silences" pass
else
  run_test "ANTHROPIC_MODEL=4.5 silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: ANTHROPIC_MODEL explicitly set to 4.6 → silent
OUT=$(unset CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-sonnet-4-6 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL=4.6 silences" pass
else
  run_test "ANTHROPIC_MODEL=4.6 silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: ANTHROPIC_MODEL set to any non-empty value → silent (treated as deliberate)
OUT=$(unset CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL=opus silences (any non-empty value)" pass
else
  run_test "ANTHROPIC_MODEL=opus silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: ANTHROPIC_MODEL unset and REMIND unset → silent (opt-in only, default off)
OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL unset, REMIND unset → silent (opt-in default)" pass
else
  run_test "ANTHROPIC_MODEL unset, REMIND unset → silent (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: ANTHROPIC_MODEL unset and REMIND=1 → emit reminder
OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; \
  CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ANTHROPIC_MODEL is unset"; then
  run_test "ANTHROPIC_MODEL unset, REMIND=1 → reminder emitted" pass
else
  run_test "ANTHROPIC_MODEL unset, REMIND=1 → reminder emitted (exit=$EXIT, out=$OUT)" fail
fi

# Test 7: Reminder includes the 4.5 model ID
OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; \
  CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "claude-sonnet-4-5-20250929"; then
  run_test "Reminder contains the 4.5 model ID for explicit pinning" pass
else
  run_test "Reminder contains the 4.5 model ID" fail
fi

# Test 8: Reminder mentions the QUIET env var for suppression
OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; \
  CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_SONNET_45_HELPER_QUIET"; then
  run_test "Reminder explains how to suppress" pass
else
  run_test "Reminder explains how to suppress" fail
fi

# Test 9: Reminder references the operator-side paths Gist
OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; \
  CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "gist.github.com/yurukusa/29d9c3ba62aa514450ba04fccc566161"; then
  run_test "Reminder links to the 5-paths Gist" pass
else
  run_test "Reminder links to the 5-paths Gist" fail
fi

# Test 10: ANTHROPIC_MODEL set to empty string is treated as unset (per [-n] semantics)
OUT=$(unset CC_SONNET_45_HELPER_QUIET; ANTHROPIC_MODEL="" CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ANTHROPIC_MODEL is unset"; then
  run_test "ANTHROPIC_MODEL='' (empty) → reminder emitted (treated as unset)" pass
else
  run_test "ANTHROPIC_MODEL='' (empty) → reminder emitted (exit=$EXIT)" fail
fi

# Test 11: Multiple invocations are idempotent (no state leaked between runs)
OUT1=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; \
  CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
OUT2=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; \
  CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if [ "$OUT1" = "$OUT2" ]; then
  run_test "Idempotent: two invocations produce identical output" pass
else
  run_test "Idempotent: two invocations produce identical output" fail
fi

# Test 12: Hook never blocks (always exits 0)
EXIT_CODES=""
for case in "QUIET=1" "ANTHROPIC_MODEL=4.5" "ANTHROPIC_MODEL=4.6" "all-unset" "REMIND=1"; do
  case "$case" in
    "QUIET=1") OUT=$(CC_SONNET_45_HELPER_QUIET=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "ANTHROPIC_MODEL=4.5") OUT=$(unset CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; ANTHROPIC_MODEL=claude-sonnet-4-5-20250929 bash "$HOOK" 2>&1); EXIT=$? ;;
    "ANTHROPIC_MODEL=4.6") OUT=$(unset CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; ANTHROPIC_MODEL=claude-sonnet-4-6 bash "$HOOK" 2>&1); EXIT=$? ;;
    "all-unset") OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_REMIND CC_SONNET_45_HELPER_QUIET; bash "$HOOK" 2>&1); EXIT=$? ;;
    "REMIND=1") OUT=$(unset ANTHROPIC_MODEL CC_SONNET_45_HELPER_QUIET; CC_SONNET_45_HELPER_REMIND=1 bash "$HOOK" 2>&1); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks (all paths exit 0)" pass
else
  run_test "Hook never blocks (exit codes: $EXIT_CODES)" fail
fi

echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
