#!/bin/bash
# Tests for context-usage-drift-alert.sh
HOOK="examples/context-usage-drift-alert.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

# Use a test-specific counter file
COUNTER_FILE="/tmp/cc-context-usage-counter-$(date +%Y%m%d)"
rm -f "$COUNTER_FILE"

# Test 1: Calls 1-49 should not warn
for i in $(seq 1 49); do
  echo '{}' | bash "$HOOK" 2>/dev/null
done
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
# Call 50 should give checkpoint
assert_contains "call 50 should checkpoint" "$OUT" "checkpoint"
assert_contains "should mention /cost" "$OUT" "/cost"

# Test 2: Calls 51-99 should not warn
for i in $(seq 51 99); do
  echo '{}' | bash "$HOOK" 2>/dev/null
done
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
# Call 100 should give strong warning
assert_contains "call 100 should warn high" "$OUT" "HIGH CONTEXT"
assert_contains "should mention /compact" "$OUT" "/compact"
assert_contains "should reference issue" "$OUT" "#50204"

# Test 3: Calls 101-149
for i in $(seq 101 149); do
  echo '{}' | bash "$HOOK" 2>/dev/null
done
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
# Call 150 should give critical warning
assert_contains "call 150 critical warning" "$OUT" "VERY HIGH"
assert_contains "should mention saving state" "$OUT" "Save"

# Test 4: Normal calls between thresholds should be silent
rm -f "$COUNTER_FILE"
echo "10" > "$COUNTER_FILE"
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
assert_not_contains "non-threshold call should be silent" "$OUT" "checkpoint"
assert_not_contains "non-threshold no warning" "$OUT" "HIGH"

# Cleanup
rm -f "$COUNTER_FILE"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
