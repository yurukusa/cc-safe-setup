#!/bin/bash
# Tests for quota-reset-cycle-monitor.sh
HOOK="examples/quota-reset-cycle-monitor.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

HISTORY="/tmp/cc-quota-reset-history"
rm -f "$HISTORY"

# Test 1: First run creates history
OUT=$(bash "$HOOK" 2>&1)
RC=$?
assert_exit "exit 0" "$RC" 0
if [ -f "$HISTORY" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: history not created"; fi

# Test 2: History contains today's date
TODAY=$(date +%Y-%m-%d)
CONTENT=$(cat "$HISTORY")
assert_contains "has today's date" "$CONTENT" "$TODAY"

# Test 3: Second run same day — no duplicate entry
bash "$HOOK" 2>/dev/null
LINES=$(wc -l < "$HISTORY")
if [ "$LINES" -eq 1 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: duplicate entry ($LINES lines)"; fi

# Test 4: History format is correct (date|weekday)
WEEKDAY=$(date +%u)
assert_contains "correct format" "$CONTENT" "$TODAY|$WEEKDAY"

# Test 5: With 7+ entries, should give info message
rm -f "$HISTORY"
for i in $(seq 1 7); do
  echo "2026-04-$(printf '%02d' $((i+10)))|$i" >> "$HISTORY"
done
# Remove today's entry so the hook will run
sed -i "/$TODAY/d" "$HISTORY"
OUT=$(bash "$HOOK" 2>&1)
assert_contains "7+ entries shows info" "$OUT" "tracking"
assert_contains "references issue" "$OUT" "#49599"

# Test 6: Exit code always 0
RC=$?
assert_exit "always exit 0" "$RC" 0

# Cleanup
rm -f "$HISTORY"

echo "quota-reset-cycle-monitor: $PASS passed, $FAIL failed"
exit $FAIL
