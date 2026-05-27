#!/bin/bash
# Tests for server-side-prompt-injection-detector.sh
HOOK="$(dirname "$0")/../examples/server-side-prompt-injection-detector.sh"
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

echo "Testing server-side-prompt-injection-detector.sh"
echo "================================================"

# Test 1: both env vars set to 1 → silent exit 0
OUT=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "both opt-outs set → silent exit 0" pass
else
  run_test "both opt-outs set → silent exit 0 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC missing → warning lists only it in Missing line
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; DISABLE_GROWTHBOOK=1 \
  bash "$HOOK" 2>&1)
EXIT=$?
MISSING_LINE=$(echo "$OUT" | grep "Missing opt-out env var")
if [ "$EXIT" = "0" ] && echo "$MISSING_LINE" | grep -q "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
    && ! echo "$MISSING_LINE" | grep -q "DISABLE_GROWTHBOOK"; then
  run_test "only CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC missing → Missing line lists only it" pass
else
  run_test "only CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC missing (Missing line: $MISSING_LINE)" fail
fi

# Test 3: DISABLE_GROWTHBOOK missing → warning mentions it
OUT=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1; unset DISABLE_GROWTHBOOK; \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "DISABLE_GROWTHBOOK"; then
  run_test "only DISABLE_GROWTHBOOK missing → warning lists it" pass
else
  run_test "only DISABLE_GROWTHBOOK missing (got: $OUT)" fail
fi

# Test 4: both missing → warning lists both
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] \
    && echo "$OUT" | grep -q "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
    && echo "$OUT" | grep -q "DISABLE_GROWTHBOOK"; then
  run_test "both missing → warning lists both vars" pass
else
  run_test "both missing → warning lists both vars (got: $OUT)" fail
fi

# Test 5: CC_PROMPT_INJECTION_DETECTOR_QUIET=1 silences regardless of opt-outs
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  CC_PROMPT_INJECTION_DETECTOR_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences warning even when opt-outs missing" pass
else
  run_test "QUIET=1 silences warning (exit=$EXIT, out=$OUT)" fail
fi

# Test 6: opt-outs set to "0" → treated as unset (warns)
OUT=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=0 DISABLE_GROWTHBOOK=0 \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
    && echo "$OUT" | grep -q "DISABLE_GROWTHBOOK"; then
  run_test "values of 0 treated as not opted-out → warning" pass
else
  run_test "values of 0 treated as not opted-out (got: $OUT)" fail
fi

# Test 7: opt-outs set to "yes" → treated as unset (only "1" counts)
OUT=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=yes DISABLE_GROWTHBOOK=yes \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"; then
  run_test "non-1 values treated as not opted-out → warning" pass
else
  run_test "non-1 values treated as not opted-out (got: $OUT)" fail
fi

# Test 8: warning includes issue reference #62061
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "#62061"; then
  run_test "warning includes issue reference #62061" pass
else
  run_test "warning includes issue reference (got: $OUT)" fail
fi

# Test 9: warning includes opt-out instruction
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"; then
  run_test "warning includes export command for opt-out" pass
else
  run_test "warning includes export command (got: $OUT)" fail
fi

# Test 10: warning includes QUIET acknowledgment path
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_PROMPT_INJECTION_DETECTOR_QUIET"; then
  run_test "warning mentions QUIET env var to silence" pass
else
  run_test "warning mentions QUIET env var (got: $OUT)" fail
fi

# Test 11: exit code is always 0 (non-blocking)
EXITS=()
for env_args in \
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_GROWTHBOOK=1" \
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" \
    "DISABLE_GROWTHBOOK=1" \
    "CC_PROMPT_INJECTION_DETECTOR_QUIET=1" \
    ""; do
  eval "env -i $env_args bash \"$HOOK\" >/dev/null 2>&1"
  EXITS+=("$?")
done
ALL_ZERO=1
for e in "${EXITS[@]}"; do
  [ "$e" != "0" ] && ALL_ZERO=0
done
if [ "$ALL_ZERO" = "1" ]; then
  run_test "exit code 0 in all 5 env configurations (non-blocking)" pass
else
  run_test "exit code 0 in all configs (got: ${EXITS[*]})" fail
fi

# Test 12: output goes to stderr, not stdout
STDOUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>/dev/null)
if [ -z "$STDOUT" ]; then
  run_test "warning written to stderr, stdout is empty" pass
else
  run_test "warning to stderr (stdout was: $STDOUT)" fail
fi

# Test 13: warning includes "ADVISORY" prefix (not "BLOCKED")
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "^ADVISORY"; then
  run_test "uses ADVISORY (non-blocking) prefix" pass
else
  run_test "uses ADVISORY prefix (got: $OUT)" fail
fi

# Test 14: warning mentions tengu_heron_brook flag name (audit-trail evidence)
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "tengu_heron_brook"; then
  run_test "warning names the GrowthBook flag (tengu_heron_brook)" pass
else
  run_test "warning names the GrowthBook flag (got: $OUT)" fail
fi

# Test 15: warning mentions client_data field (bootstrap injection path)
OUT=$(unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; unset DISABLE_GROWTHBOOK; \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "client_data"; then
  run_test "warning names client_data bootstrap field" pass
else
  run_test "warning names client_data (got: $OUT)" fail
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
