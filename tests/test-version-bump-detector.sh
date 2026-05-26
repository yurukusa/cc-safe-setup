#!/bin/bash
# Tests for version-bump-detector.sh
HOOK="$(dirname "$0")/../examples/version-bump-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-vbump-test.XXXXXX"
}

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

echo "Testing version-bump-detector.sh"
echo "================================="

# Test 1: DISABLE=1 → exit 0, no state file written
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo '{}' | CC_VERSION_BUMP_DISABLE=1 \
  CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.143" \
  bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$STATE" ]; then
  run_test "DISABLE=1 → exit 0, no state written" pass
else
  run_test "DISABLE=1 → exit 0, no state written (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 2: First run → records version, no warning, event=first_run logged
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.143" bash "$HOOK" 2>/dev/null)
STATE_VAL=$(cat "$STATE" 2>/dev/null)
if [ "$STATE_VAL" = "2.1.143" ] && [ -z "$OUT" ] && grep -q '"event":"first_run"' "$LOG"; then
  run_test "first run → records version, no warning, event=first_run logged" pass
else
  run_test "first run → records version, no warning (state=$STATE_VAL, out=$OUT)" fail
fi
rm -rf "$TEST_DIR"

# Test 3: Same version as previous → silent, no log append
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo "2.1.143" > "$STATE"
echo '{"ts":"2026-05-25T00:00:00Z","version":"2.1.143","event":"first_run"}' > "$LOG"
BEFORE_LINES=$(wc -l < "$LOG")
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.143" bash "$HOOK" 2>/dev/null)
AFTER_LINES=$(wc -l < "$LOG")
if [ -z "$OUT" ] && [ "$BEFORE_LINES" = "$AFTER_LINES" ]; then
  run_test "same version → silent, no log append" pass
else
  run_test "same version → silent (out=$OUT, before=$BEFORE_LINES after=$AFTER_LINES)" fail
fi
rm -rf "$TEST_DIR"

# Test 4: Version bump → warn with previous and current versions, log appended
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo "2.1.143" > "$STATE"
echo '{"ts":"2026-05-25T00:00:00Z","version":"2.1.143","event":"first_run"}' > "$LOG"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.144" bash "$HOOK" 2>/dev/null)
if echo "$OUT" | grep -q "Previous session: 2.1.143" && \
   echo "$OUT" | grep -q "Current session:  2.1.144" && \
   grep -q '"event":"version_bump"' "$LOG" && \
   grep -q '"previous":"2.1.143"' "$LOG" && \
   grep -q '"version":"2.1.144"' "$LOG"; then
  run_test "version bump → warn with both versions, log appended" pass
else
  run_test "version bump → warn with both versions (out=$OUT)" fail
fi
rm -rf "$TEST_DIR"

# Test 5: Version bump output is valid JSON with hookSpecificOutput
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo "2.1.143" > "$STATE"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.144" bash "$HOOK" 2>/dev/null)
if echo "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 && \
   echo "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("VERSION BUMP")' >/dev/null 2>&1; then
  run_test "version bump output is valid JSON with hookSpecificOutput" pass
else
  run_test "version bump output is valid JSON (out=$OUT)" fail
fi
rm -rf "$TEST_DIR"

# Test 6: Invalid (non-semver) override → silent skip
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="not-a-version" bash "$HOOK" 2>/dev/null)
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$STATE" ]; then
  run_test "non-semver override → silent skip" pass
else
  run_test "non-semver override → silent skip (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 7: Empty override → silent skip
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="" bash "$HOOK" 2>/dev/null)
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "empty override → silent skip" pass
else
  run_test "empty override → silent skip (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 8: Multiple bumps in sequence → log records all transitions
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.143" bash "$HOOK" 2>/dev/null
echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.144" bash "$HOOK" 2>/dev/null
echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.145" bash "$HOOK" 2>/dev/null
LINE_COUNT=$(wc -l < "$LOG")
BUMP_COUNT=$(grep -c '"event":"version_bump"' "$LOG")
FIRST_RUN=$(grep -c '"event":"first_run"' "$LOG")
if [ "$LINE_COUNT" = "3" ] && [ "$BUMP_COUNT" = "2" ] && [ "$FIRST_RUN" = "1" ]; then
  run_test "3 sessions with 2 bumps → 1 first_run + 2 version_bump in log" pass
else
  run_test "3 sessions with 2 bumps (lines=$LINE_COUNT bumps=$BUMP_COUNT first=$FIRST_RUN)" fail
fi
rm -rf "$TEST_DIR"

# Test 9: State file path with nested dir is auto-created
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/nested/dir/state"
LOG="$TEST_DIR/nested/dir/log.jsonl"
echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.143" bash "$HOOK" 2>/dev/null
if [ -f "$STATE" ] && [ -f "$LOG" ]; then
  run_test "nested dir paths auto-created" pass
else
  run_test "nested dir paths auto-created (state_exists=$([ -f "$STATE" ] && echo yes || echo no))" fail
fi
rm -rf "$TEST_DIR"

# Test 10: Warning references upstream cluster issues
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo "2.1.143" > "$STATE"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.144" bash "$HOOK" 2>/dev/null)
if echo "$OUT" | grep -q '158436e88d169406593d55bd84f0d7e9'; then
  run_test "warning references Pro Max field guide Gist" pass
else
  run_test "warning references Pro Max field guide Gist (out=$OUT)" fail
fi
rm -rf "$TEST_DIR"

# Test 11: Warning mentions cache-creation-drift-detector as companion
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
echo "2.1.143" > "$STATE"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.144" bash "$HOOK" 2>/dev/null)
if echo "$OUT" | grep -q 'cache-creation-drift-detector'; then
  run_test "warning mentions companion cache-creation-drift-detector" pass
else
  run_test "warning mentions companion cache-creation-drift-detector (out=$OUT)" fail
fi
rm -rf "$TEST_DIR"

# Test 12: Whitespace in state file is tolerated
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state"
LOG="$TEST_DIR/log.jsonl"
printf "  2.1.143  \n" > "$STATE"
OUT=$(echo '{}' | CC_VERSION_BUMP_STATE="$STATE" CC_VERSION_BUMP_LOG="$LOG" \
  CC_VERSION_BUMP_OVERRIDE="2.1.143" bash "$HOOK" 2>/dev/null)
if [ -z "$OUT" ]; then
  run_test "whitespace in state file is tolerated (no false bump)" pass
else
  run_test "whitespace in state file (out=$OUT)" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
