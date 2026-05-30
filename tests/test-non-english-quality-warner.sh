#!/bin/bash
# Tests for non-english-quality-warner.sh
HOOK="$(dirname "$0")/../examples/non-english-quality-warner.sh"
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
  unset CC_NON_ENGLISH_QUALITY_WARNER_REMIND
  unset CC_NON_ENGLISH_QUALITY_WARNER_DISABLE
  unset CC_NON_ENGLISH_QUALITY_WARNER_QUIET
}

echo "Testing non-english-quality-warner.sh"
echo "======================================"

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
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "non-english-quality-warner"; then
  run_test "REMIND=1 emits the advisory" pass
else
  run_test "REMIND=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: REMIND=1 + DISABLE=1 → silent (DISABLE wins)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 CC_NON_ENGLISH_QUALITY_WARNER_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=1 + DISABLE=1 silent (DISABLE wins)" pass
else
  run_test "REMIND+DISABLE (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: REMIND=1 + QUIET=1 → silent (QUIET wins)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 CC_NON_ENGLISH_QUALITY_WARNER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=1 + QUIET=1 silent (QUIET wins)" pass
else
  run_test "REMIND+QUIET (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: REMIND empty string → silent (not "1")
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND="" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND='' is silent (not '1')" pass
else
  run_test "REMIND='' (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: REMIND=0 → silent
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=0 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=0 is silent" pass
else
  run_test "REMIND=0 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: REMIND=true → silent (only literal "1" enables)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=true bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "REMIND=true is silent (only literal '1' enables)" pass
else
  run_test "REMIND=true (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 8: Advisory cites issue #62961 (Korean evidence)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "62961"; then
  run_test "Advisory cites issue #62961" pass
else
  run_test "Advisory cites #62961 (out=$OUT)" fail
fi

# Test 9: Advisory cites 18× signal
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "18.0×"; then
  run_test "Advisory cites 18× regression signal" pass
else
  run_test "Advisory cites 18× (out_len=${#OUT})" fail
fi

# Test 10: Advisory cites the three workaround paths
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
HAS1=$(printf '%s' "$OUT" | grep -c "1) Pin formal register")
HAS2=$(printf '%s' "$OUT" | grep -c "2) Switch to Sonnet")
HAS3=$(printf '%s' "$OUT" | grep -c "3) Post-process the output")
if [ "$HAS1" = "1" ] && [ "$HAS2" = "1" ] && [ "$HAS3" = "1" ]; then
  run_test "Advisory contains all three workaround paths" pass
else
  run_test "Three paths (has1=$HAS1 has2=$HAS2 has3=$HAS3)" fail
fi

# Test 11: Advisory references the version timeline (2.1.126, 2.1.132)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
H126=$(printf '%s' "$OUT" | grep -c "2.1.126")
H132=$(printf '%s' "$OUT" | grep -c "2.1.132")
if [ "$H126" -ge "1" ] && [ "$H132" -ge "1" ]; then
  run_test "Advisory references version timeline 2.1.126 and 2.1.132" pass
else
  run_test "Version timeline (h126=$H126 h132=$H132)" fail
fi

# Test 12: Advisory shows how to disable (unset REMIND and/or QUIET=1)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "unset CC_NON_ENGLISH_QUALITY_WARNER_REMIND" \
   && printf '%s' "$OUT" | grep -q "export CC_NON_ENGLISH_QUALITY_WARNER_QUIET=1"; then
  run_test "Advisory explains how to disable" pass
else
  run_test "Disable instructions (out_len=${#OUT})" fail
fi

# Test 13: Advisory references the field guide gist
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "gist.github.com"; then
  run_test "Advisory references the field guide gist" pass
else
  run_test "Field guide gist link (out_len=${#OUT})" fail
fi

# Test 14: Advisory includes Korean and Japanese formal-register examples
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
HAS_KO=$(printf '%s' "$OUT" | grep -c "박다")
HAS_JA=$(printf '%s' "$OUT" | grep -c "formal register に固定")
if [ "$HAS_KO" -ge "1" ] && [ "$HAS_JA" -ge "1" ]; then
  run_test "Advisory contains Korean and Japanese examples" pass
else
  run_test "Multilingual examples (has_ko=$HAS_KO has_ja=$HAS_JA)" fail
fi

# Test 15: Advisory recommends Sonnet swap with concrete export command
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "export ANTHROPIC_MODEL=claude-sonnet-4-7"; then
  run_test "Advisory shows concrete Sonnet swap command" pass
else
  run_test "Sonnet swap command (out_len=${#OUT})" fail
fi

# Test 16: Never blocks — exit 0 even when emitting
reset_env
CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 even when emitting)" pass
else
  run_test "Exit code on emit (exit=$EXIT)" fail
fi

# Test 17: Never blocks — exit 0 when silent (default)
reset_env
bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "Never blocks (exit=0 when silent)" pass
else
  run_test "Exit code when silent (exit=$EXIT)" fail
fi

# Test 18: Hook handles no stdin input gracefully (SessionStart hooks may not pipe)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" < /dev/null 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && printf '%s' "$OUT" | grep -q "non-english-quality-warner"; then
  run_test "Handles no-stdin gracefully (SessionStart pattern)" pass
else
  run_test "No-stdin (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 19: Advisory is non-trivial size (sanity check)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if [ "${#OUT}" -ge "1500" ]; then
  run_test "Advisory has substantial content (>=1500 chars)" pass
else
  run_test "Advisory size (chars=${#OUT})" fail
fi

# Test 20: Advisory acknowledges the regression is server-side (no client fix)
reset_env
OUT=$(CC_NON_ENGLISH_QUALITY_WARNER_REMIND=1 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "server-side"; then
  run_test "Advisory acknowledges server-side cause (no client fix)" pass
else
  run_test "Server-side framing (out_len=${#OUT})" fail
fi

echo "======================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
