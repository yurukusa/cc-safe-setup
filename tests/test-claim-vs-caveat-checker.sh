#!/bin/bash
# Tests for claim-vs-caveat-checker.sh — verifies that confident
# claims overlapping with earlier caveats in the same transcript
# emit a non-blocking note (or block when CLAIM_CAVEAT_BLOCK=1).
HOOK="examples/claim-vs-caveat-checker.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

# Setup temp transcript
TMPDIR=$(mktemp -d)
TRAP_FILE="$TMPDIR/transcript.jsonl"

make_input() {
  jq -n --arg t "$1" '{transcript_path: $t}'
}

write_transcript() {
  : > "$TRAP_FILE"
  for line in "$@"; do
    echo "$line" >> "$TRAP_FILE"
  done
}

# Test 1: empty transcript_path → exit 0 silently
INPUT=$(jq -n '{}')
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty transcript_path exits 0" "$RC" 0
assert_not_contains "empty transcript no output" "$OUT" "claim-vs-caveat"

# Test 2: missing transcript file → exit 0 silently
INPUT=$(make_input "/nonexistent/path.jsonl")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing transcript exits 0" "$RC" 0

# Test 3: transcript with only confident claim, no caveat → no warning
write_transcript \
  '{"role":"user","content":"check the trade"}' \
  '{"role":"assistant","content":"The trade is guaranteed to succeed."}'
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "claim-only exits 0" "$RC" 0
assert_not_contains "claim-only no warning" "$OUT" "claim-vs-caveat"

# Test 4: transcript with only caveat, no claim → no warning
write_transcript \
  '{"role":"user","content":"check the trade"}' \
  '{"role":"assistant","content":"There is a slippage risk."}'
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "caveat-only exits 0" "$RC" 0
assert_not_contains "caveat-only no warning" "$OUT" "claim-vs-caveat"

# Test 5: caveat earlier + confident claim later → warning emitted
write_transcript \
  '{"role":"user","content":"check the trade"}' \
  '{"role":"assistant","content":"There is a slippage risk on this position."}' \
  '{"role":"user","content":"deploy the fix"}' \
  '{"role":"assistant","content":"The fix is guaranteed to handle the slippage."}'
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "claim+caveat exits 0 in warn-only" "$RC" 0
assert_contains "claim+caveat warns" "$OUT" "claim-vs-caveat"
assert_contains "warning includes claim term" "$OUT" "guaranteed"

# Test 6: same setup with CLAIM_CAVEAT_BLOCK=1 → block JSON
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | CLAIM_CAVEAT_BLOCK=1 bash "$HOOK" 2>&1)
RC=$?
assert_exit "block mode exits 0 (decision-block)" "$RC" 0
assert_contains "block mode emits decision-block" "$OUT" '"decision":"block"'
assert_contains "block JSON has reason" "$OUT" '"reason"'

# Test 7: Japanese claim + caveat
write_transcript \
  '{"role":"user","content":"取引の点検"}' \
  '{"role":"assistant","content":"この銘柄には滑りの危険があります。"}' \
  '{"role":"user","content":"修正を出荷"}' \
  '{"role":"assistant","content":"修正で完璧に直った状態です。"}'
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "JP claim+caveat exits 0" "$RC" 0
assert_contains "JP claim+caveat warns" "$OUT" "claim-vs-caveat"

# Test 8: window respects CLAIM_CAVEAT_WINDOW (caveat outside window → no warn)
> "$TRAP_FILE"
for i in $(seq 1 60); do
  echo '{"role":"user","content":"filler"}' >> "$TRAP_FILE"
  echo '{"role":"assistant","content":"filler reply"}' >> "$TRAP_FILE"
done
echo '{"role":"assistant","content":"There is a slippage risk."}' >> "$TRAP_FILE"
echo '{"role":"user","content":"deploy"}' >> "$TRAP_FILE"
echo '{"role":"assistant","content":"The fix is guaranteed."}' >> "$TRAP_FILE"
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | CLAIM_CAVEAT_WINDOW=2 bash "$HOOK" 2>&1)
RC=$?
assert_exit "narrow window exits 0" "$RC" 0
assert_not_contains "narrow window suppresses old caveat" "$OUT" "claim-vs-caveat"

# Test 9: wide window picks up the caveat
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | CLAIM_CAVEAT_WINDOW=10 bash "$HOOK" 2>&1)
RC=$?
assert_exit "wide window exits 0" "$RC" 0
assert_contains "wide window detects" "$OUT" "claim-vs-caveat"

# Test 10: real-world #57288 reproduction — agent's words from the trade case
write_transcript \
  '{"role":"user","content":"check the position"}' \
  '{"role":"assistant","content":"After the modification, the SL is close to the entry price (+0.11%). On a fast move, slippage on the small protective margin may be noticeable."}' \
  '{"role":"user","content":"deploy"}' \
  '{"role":"assistant","content":"1INCHUSDT cannot close at a loss now."}'
INPUT=$(make_input "$TRAP_FILE")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "57288 repro exits 0" "$RC" 0
assert_contains "57288 repro warns" "$OUT" "claim-vs-caveat"
assert_contains "57288 mentions slippage" "$OUT" "slippage"

# Cleanup
rm -rf "$TMPDIR"

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && echo "OK" || exit 1
