#!/bin/bash
# Tests for read-loop-detector.sh
HOOK="examples/read-loop-detector.sh"
PASS=0 FAIL=0

assert_exit() {
  if [ "$2" -eq "$3" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"
  fi
}
assert_contains() {
  if printf '%s' "$2" | grep -q "$3"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"
  fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -q "$3"; then
    FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"
  else
    PASS=$((PASS+1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

SESSION="test-session-$$"
PAYLOAD='{"session_id":"'"$SESSION"'","tool_name":"Read","tool_input":{"file_path":"/repo/src/foo.ts"}}'

# Test 1: Non-Read tool — pass through silently, no log
OUT=$(printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}' | \
  CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "non-Read tool exits 0" $? 0
assert_not_contains "non-Read no warning" "$OUT" "fired"

# Test 2: Missing file_path — exit silently
OUT=$(printf '{"session_id":"s1","tool_name":"Read","tool_input":{}}' | \
  CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "missing file_path exits 0" $? 0
assert_not_contains "missing file_path no warning" "$OUT" "fired"

# Test 3: First Read of a path — no warning, log file exists with 1 entry
OUT=$(printf '%s' "$PAYLOAD" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "first read exits 0" $? 0
assert_not_contains "first read no warning" "$OUT" "fired"
LOG_FILE="$TMPDIR/cc-read-loop-${SESSION}.log"
assert_contains "log file recorded path" "$(cat "$LOG_FILE")" "/repo/src/foo.ts"

# Test 4: Second Read same path under default threshold (3) — still no warning
OUT=$(printf '%s' "$PAYLOAD" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "second read exits 0" $? 0
assert_not_contains "second read no warning" "$OUT" "fired"

# Test 5: Third Read same path — warning fires (count >= 3)
OUT=$(printf '%s' "$PAYLOAD" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "third read exits 0" $? 0
assert_contains "third read warns" "$OUT" "fired 3 times"
assert_contains "third read names file" "$OUT" "/repo/src/foo.ts"
assert_contains "third read suggests escape" "$OUT" "Stop reading"

# Test 6: Fourth Read — warning still fires with updated count
OUT=$(printf '%s' "$PAYLOAD" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "fourth read exits 0" $? 0
assert_contains "fourth read shows count 4" "$OUT" "fired 4 times"

# Test 7: Custom threshold via env var (threshold=2 → warn on 2nd read of new path)
SESSION2="test-session2-$$"
PAY2='{"session_id":"'"$SESSION2"'","tool_name":"Read","tool_input":{"file_path":"/repo/src/bar.ts"}}'
OUT=$(printf '%s' "$PAY2" | CC_READ_LOOP_LOG_DIR="$TMPDIR" CC_READ_LOOP_THRESHOLD=2 bash "$HOOK" 2>&1)
assert_exit "threshold=2 first read exits 0" $? 0
assert_not_contains "threshold=2 first no warn" "$OUT" "fired"

OUT=$(printf '%s' "$PAY2" | CC_READ_LOOP_LOG_DIR="$TMPDIR" CC_READ_LOOP_THRESHOLD=2 bash "$HOOK" 2>&1)
assert_exit "threshold=2 second read exits 0" $? 0
assert_contains "threshold=2 second read warns" "$OUT" "fired 2 times"

# Test 8: Different files in same session — counted independently
SESSION3="test-session3-$$"
PAY_A='{"session_id":"'"$SESSION3"'","tool_name":"Read","tool_input":{"file_path":"/a.ts"}}'
PAY_B='{"session_id":"'"$SESSION3"'","tool_name":"Read","tool_input":{"file_path":"/b.ts"}}'
printf '%s' "$PAY_A" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" >/dev/null 2>&1
printf '%s' "$PAY_A" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" >/dev/null 2>&1
OUT=$(printf '%s' "$PAY_B" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "different file in same session exits 0" $? 0
assert_not_contains "different file does not inherit count" "$OUT" "fired"

# Test 9: Different sessions — counted independently
SESSION_X="x-$$"
SESSION_Y="y-$$"
PAY_X='{"session_id":"'"$SESSION_X"'","tool_name":"Read","tool_input":{"file_path":"/shared.ts"}}'
PAY_Y='{"session_id":"'"$SESSION_Y"'","tool_name":"Read","tool_input":{"file_path":"/shared.ts"}}'
for _ in 1 2 3; do
    printf '%s' "$PAY_X" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" >/dev/null 2>&1
done
# Y session has only 1 read of shared.ts, no warning expected
OUT=$(printf '%s' "$PAY_Y" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "session Y first read exits 0" $? 0
assert_not_contains "session Y not affected by session X" "$OUT" "fired"

# Test 10: CC_READ_LOOP_DISABLE=1 — short-circuit silently
OUT=$(printf '%s' "$PAYLOAD" | CC_READ_LOOP_LOG_DIR="$TMPDIR" CC_READ_LOOP_DISABLE=1 bash "$HOOK" 2>&1)
assert_exit "disabled exits 0" $? 0
assert_not_contains "disabled no output" "$OUT" "fired"

# Test 11: Invalid threshold (non-numeric) — falls back to default 3
SESSION_INV="inv-$$"
PAY_INV='{"session_id":"'"$SESSION_INV"'","tool_name":"Read","tool_input":{"file_path":"/x.ts"}}'
for _ in 1 2; do
    printf '%s' "$PAY_INV" | CC_READ_LOOP_LOG_DIR="$TMPDIR" CC_READ_LOOP_THRESHOLD=abc bash "$HOOK" >/dev/null 2>&1
done
# Two reads with invalid threshold → falls back to 3 → no warning yet
OUT=$(printf '%s' "$PAY_INV" | CC_READ_LOOP_LOG_DIR="$TMPDIR" CC_READ_LOOP_THRESHOLD=abc bash "$HOOK" 2>&1)
assert_exit "invalid threshold exits 0" $? 0
# 3rd read should warn
assert_contains "invalid threshold defaults to 3" "$OUT" "fired 3 times"

# Test 12: File path with spaces — handled as literal string
SESSION_SP="sp-$$"
PAY_SP='{"session_id":"'"$SESSION_SP"'","tool_name":"Read","tool_input":{"file_path":"/path with spaces/foo.md"}}'
for _ in 1 2 3; do
    OUT=$(printf '%s' "$PAY_SP" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
done
assert_exit "spaces path exits 0" $? 0
assert_contains "spaces path warns" "$OUT" "fired 3 times"
assert_contains "spaces path preserved" "$OUT" "/path with spaces/foo.md"

# Test 13: Always non-blocking even when warning fires
OUT=$(printf '%s' "$PAYLOAD" | CC_READ_LOOP_LOG_DIR="$TMPDIR" bash "$HOOK" 2>&1)
assert_exit "warning still exits 0" $? 0

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
