#!/bin/bash
# Tests for aup-false-positive-helper.sh
HOOK="$(dirname "$0")/../examples/aup-false-positive-helper.sh"
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

echo "Testing aup-false-positive-helper.sh"
echo "===================================="

# Test 1: QUIET=1 always silences, regardless of other state
OUT=$(unset ANTHROPIC_MODEL; CC_AUP_FALSE_POSITIVE_HELPER_QUIET=1 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 \
  ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences even when Opus + REMIND=1" pass
else
  run_test "QUIET=1 silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: ANTHROPIC_MODEL unset → silent (default routing, no specific advisory)
OUT=$(unset ANTHROPIC_MODEL CC_AUP_FALSE_POSITIVE_HELPER_REMIND CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL unset → silent" pass
else
  run_test "ANTHROPIC_MODEL unset → silent (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: ANTHROPIC_MODEL=Sonnet variant → silent (unaffected by cluster)
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_REMIND CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-sonnet-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Sonnet pinned + REMIND=1 → silent (unaffected)" pass
else
  run_test "Sonnet pinned silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: ANTHROPIC_MODEL=Sonnet 4.6 → silent
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_REMIND CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-sonnet-4-6 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Sonnet 4.6 pinned + REMIND=1 → silent" pass
else
  run_test "Sonnet 4.6 silences (exit=$EXIT)" fail
fi

# Test 5: Opus pinned but REMIND unset → silent (opt-in only)
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_REMIND CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Opus pinned, REMIND unset → silent (opt-in default off)" pass
else
  run_test "Opus pinned, REMIND unset (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: Opus + REMIND=1 → emit advisory
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ANTHROPIC_MODEL is pinned"; then
  run_test "Opus + REMIND=1 → advisory emitted" pass
else
  run_test "Opus + REMIND=1 → advisory (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: Opus 4.6 1M variant + REMIND=1 → also emits (lowercase opus pattern)
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-6-1m CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "ANTHROPIC_MODEL is pinned"; then
  run_test "Opus 4.6 1M variant + REMIND=1 → advisory emitted" pass
else
  run_test "Opus 4.6 1M emits advisory" fail
fi

# Test 8: Advisory mentions the four operator-side mitigation paths
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "1\." && echo "$OUT" | grep -q "2\." && echo "$OUT" | grep -q "3\." && echo "$OUT" | grep -q "4\."; then
  run_test "Advisory enumerates four mitigation paths" pass
else
  run_test "Advisory enumerates four mitigation paths" fail
fi

# Test 9: Advisory mentions Sonnet as the model swap path
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -qi "sonnet"; then
  run_test "Advisory recommends Sonnet for model swap path" pass
else
  run_test "Advisory mentions Sonnet" fail
fi

# Test 10: Advisory mentions CVP program
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -qi "cyber.verification.program\|CVP"; then
  run_test "Advisory references the Cyber Verification Program" pass
else
  run_test "Advisory references CVP" fail
fi

# Test 11: Advisory mentions the QUIET suppress env var
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_AUP_FALSE_POSITIVE_HELPER_QUIET"; then
  run_test "Advisory explains how to suppress with QUIET=1" pass
else
  run_test "Advisory mentions QUIET" fail
fi

# Test 12: Advisory references the upstream GitHub tracker issues
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "github.com/anthropics/claude-code/issues"; then
  run_test "Advisory links upstream issue tracker entries" pass
else
  run_test "Advisory links upstream tracker" fail
fi

# Test 13: ANTHROPIC_MODEL='' (empty) treated as unset → silent
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL="" CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL='' (empty) → silent (treated as unset)" pass
else
  run_test "Empty ANTHROPIC_MODEL silences (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 14: Mixed-case Opus pattern (e.g., capitalized OPUS) → emits
OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=Claude-Opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "ANTHROPIC_MODEL is pinned"; then
  run_test "Mixed-case 'Opus' pattern → advisory emitted" pass
else
  run_test "Mixed-case Opus emits" fail
fi

# Test 15: Idempotency — two invocations produce identical output
OUT1=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
OUT2=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; \
  ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1)
if [ "$OUT1" = "$OUT2" ]; then
  run_test "Idempotent: two invocations produce identical output" pass
else
  run_test "Idempotent advisory output" fail
fi

# Test 16: Hook never blocks — all paths exit 0
EXIT_CODES=""
for case in "QUIET=1" "unset" "Sonnet+REMIND" "Opus-no-REMIND" "Opus+REMIND" "empty-model"; do
  case "$case" in
    "QUIET=1") OUT=$(CC_AUP_FALSE_POSITIVE_HELPER_QUIET=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "unset") OUT=$(unset ANTHROPIC_MODEL CC_AUP_FALSE_POSITIVE_HELPER_REMIND CC_AUP_FALSE_POSITIVE_HELPER_QUIET; bash "$HOOK" 2>&1); EXIT=$? ;;
    "Sonnet+REMIND") OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; ANTHROPIC_MODEL=claude-sonnet-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "Opus-no-REMIND") OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_REMIND CC_AUP_FALSE_POSITIVE_HELPER_QUIET; ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "Opus+REMIND") OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; ANTHROPIC_MODEL=claude-opus-4-7 CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "empty-model") OUT=$(unset CC_AUP_FALSE_POSITIVE_HELPER_QUIET; ANTHROPIC_MODEL="" CC_AUP_FALSE_POSITIVE_HELPER_REMIND=1 bash "$HOOK" 2>&1); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks (all 6 paths exit 0)" pass
else
  run_test "Hook never blocks (exit codes: $EXIT_CODES)" fail
fi

echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
