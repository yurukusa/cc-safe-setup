#!/bin/bash
# Tests for subagent-spawn-rate-monitor.sh
HOOK="examples/subagent-spawn-rate-monitor.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

# Cleanup state
rm -f /tmp/cc-subagent-spawn-counter /tmp/cc-subagent-spawn-window

# Test 1: First spawn should not warn
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
assert_not_contains "first spawn no warn" "$OUT" "HIGH SUBAGENT"

# Test 2-5: Spawns 2-5 should not warn
for i in 2 3 4 5; do
  OUT=$(echo '{}' | bash "$HOOK" 2>&1)
  assert_not_contains "spawn $i no warn" "$OUT" "HIGH SUBAGENT"
done

# Test 6: 6th spawn (>5 threshold) should warn
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
assert_contains "6th spawn should warn" "$OUT" "HIGH SUBAGENT"
assert_contains "should mention token cost" "$OUT" "4.7K"
assert_contains "should reference issue" "$OUT" "#50213"

# Test 7: Reset counter, verify no warning after reset
rm -f /tmp/cc-subagent-spawn-counter /tmp/cc-subagent-spawn-window
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
assert_not_contains "after reset no warn" "$OUT" "HIGH SUBAGENT"

# Test 8: Window expiry reset
echo "1" > /tmp/cc-subagent-spawn-counter
echo "$(($(date +%s) - 400))" > /tmp/cc-subagent-spawn-window
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
assert_not_contains "expired window resets count" "$OUT" "HIGH SUBAGENT"

# Cleanup
rm -f /tmp/cc-subagent-spawn-counter /tmp/cc-subagent-spawn-window

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
