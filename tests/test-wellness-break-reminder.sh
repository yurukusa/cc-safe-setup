#!/bin/bash
# Tests for wellness-break-reminder.sh
HOOK="examples/wellness-break-reminder.sh"
PASS=0 FAIL=0

assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }
assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }

# Use a sandboxed HOME so the test never touches real flags
TMP_HOME=$(mktemp -d)
mkdir -p "$TMP_HOME/.claude"
START_FLAG="$TMP_HOME/.claude/wellness-session-start"
LAST_REMIND="$TMP_HOME/.claude/wellness-last-reminder"

PAYLOAD='{"session_id":"w1","tool_name":"Bash"}'

# Test 1: first invocation creates START_FLAG and exits 0 silently
rm -f "$START_FLAG" "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "first call exits 0" "$?" 0
assert_not_contains "first call silent (no body emoji)" "$OUT" "🫖"
[ -f "$START_FLAG" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: START_FLAG not created"; }

# Test 2: invocation before threshold stays silent
# Simulate "session started 30 minutes ago" by writing a back-dated epoch
date -d '30 minutes ago' +%s > "$START_FLAG" 2>/dev/null || \
  echo $(( $(date +%s) - 1800 )) > "$START_FLAG"
: > "$LAST_REMIND"  # No previous reminder
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "before-threshold exits 0" "$?" 0
assert_not_contains "before-threshold silent" "$OUT" "セッション"

# Test 3: past threshold (95 minutes) emits reminder to stderr
echo $(( $(date +%s) - 5700 )) > "$START_FLAG"  # 95 min ago
rm -f "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "past-threshold exits 0" "$?" 0
assert_contains "past-threshold emits reminder" "$OUT" "セッション"
assert_contains "past-threshold uses 2hr-tier emoji" "$OUT" "🫖"
[ -f "$LAST_REMIND" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: LAST_REMIND not written"; }

# Test 4: repeat invocation within REPEAT_INTERVAL is throttled
# (LAST_REMIND was just written by test 3)
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "throttle exits 0" "$?" 0
assert_not_contains "throttle suppresses reminder" "$OUT" "セッション"

# Test 5: after REPEAT_INTERVAL elapses, reminder fires again
# Simulate "last reminder 31 minutes ago"
echo $(( $(date +%s) - 1860 )) > "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "post-throttle exits 0" "$?" 0
assert_contains "post-throttle emits again" "$OUT" "セッション"

# Test 6: CC_WELLNESS_OFF=1 silences unconditionally
echo $(( $(date +%s) - 5700 )) > "$START_FLAG"  # 95 min ago, would normally fire
rm -f "$LAST_REMIND"
OUT=$(CC_WELLNESS_OFF=1 printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" CC_WELLNESS_OFF=1 bash "$HOOK" 2>&1)
assert_exit "kill switch exits 0" "$?" 0
assert_not_contains "kill switch fully silent" "$OUT" "セッション"

# Test 7: Custom CC_WELLNESS_FIRST_MIN lowers threshold
echo $(( $(date +%s) - 600 )) > "$START_FLAG"  # 10 min ago
rm -f "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" CC_WELLNESS_FIRST_MIN=5 bash "$HOOK" 2>&1)
assert_exit "custom threshold exits 0" "$?" 0
assert_contains "custom 5-min threshold fires at 10min" "$OUT" "セッション"

# Test 8: stale flag (>12h old) is reset; first-call semantics restored
echo $(( $(date +%s) - 50000 )) > "$START_FLAG"  # ~14h ago
: > "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "stale flag exits 0" "$?" 0
assert_not_contains "stale flag suppresses reminder" "$OUT" "セッション"
# After this run the flag should be fresh (within a minute of now)
NEW_FLAG=$(cat "$START_FLAG")
NOW=$(date +%s)
DELTA=$(( NOW - NEW_FLAG ))
if [ "$DELTA" -lt 60 ] && [ "$DELTA" -ge 0 ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "FAIL: stale flag not reset to current time (delta=$DELTA)"
fi

# Test 9: empty/missing START_EPOCH content treated like fresh session
echo "" > "$START_FLAG"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "empty flag exits 0" "$?" 0
assert_not_contains "empty flag silent" "$OUT" "セッション"

# Test 10: 4-hour tier emits the longer-session message (different emoji/wording)
echo $(( $(date +%s) - 16200 )) > "$START_FLAG"  # 4h30m ago
rm -f "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "4hr tier exits 0" "$?" 0
assert_contains "4hr tier uses moon emoji" "$OUT" "🌙"
assert_not_contains "4hr tier omits 2hr emoji" "$OUT" "🫖"

# Test 11: 2-4hr tier uses 🪟 (window) emoji
echo $(( $(date +%s) - 9000 )) > "$START_FLAG"  # 2h30m ago
rm -f "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "mid-tier exits 0" "$?" 0
assert_contains "mid-tier uses window emoji" "$OUT" "🪟"

# Test 12 (PR #137 Codex review regression): empty LAST_REMIND file does not
# raise integer error and does not bypass throttle. Repro: stale-reset path
# `: > "$LAST_REMIND"` leaves the file empty; previous code stored ''  in
# LAST_EPOCH, which made `[ "$LAST_EPOCH" -gt 0 ]` raise "integer expression
# expected" on stricter shells and silently bypassed throttle on others.
echo $(( $(date +%s) - 9000 )) > "$START_FLAG"  # 2h30m ago, past threshold
: > "$LAST_REMIND"  # empty file (the reported bug surface)
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "empty LAST_REMIND exits 0 cleanly" "$?" 0
assert_not_contains "empty LAST_REMIND raises no integer error" "$OUT" "integer expression"
# First call past threshold with empty LAST_REMIND should still emit the reminder
# (LAST_EPOCH=0 → throttle gate `[ -gt 0 ]` is false → reminder fires).
assert_contains "empty LAST_REMIND still emits reminder" "$OUT" "🪟"
# After the call, LAST_REMIND should now contain a valid epoch (numeric)
LAST_REMIND_AFTER=$(cat "$LAST_REMIND")
case "$LAST_REMIND_AFTER" in
    ''|*[!0-9]*) FAIL=$((FAIL+1)); echo "FAIL: LAST_REMIND post-call not numeric (got '$LAST_REMIND_AFTER')" ;;
    *) PASS=$((PASS+1)) ;;
esac

# Test 13 (PR #137 Codex review regression, companion): non-numeric garbage in
# LAST_REMIND is also normalized to 0 — tests case statement, not just empty.
echo $(( $(date +%s) - 9000 )) > "$START_FLAG"
echo "garbage_text" > "$LAST_REMIND"
OUT=$(printf '%s' "$PAYLOAD" | HOME="$TMP_HOME" bash "$HOOK" 2>&1)
assert_exit "non-numeric LAST_REMIND exits 0 cleanly" "$?" 0
assert_not_contains "non-numeric LAST_REMIND raises no integer error" "$OUT" "integer expression"

rm -rf "$TMP_HOME"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
