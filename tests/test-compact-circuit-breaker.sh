#!/bin/bash
# Tests for compact-circuit-breaker.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/compact-circuit-breaker.sh"
STATE_DIR="/tmp/.cc-compact-circuit-breaker"
STATE_FILE="$STATE_DIR/compaction-log"
PASS=0; FAIL=0; TOTAL=0

run_test() {
  local desc="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "✅ $desc"
  else
    local code=$?
    if [ "$code" -eq 2 ]; then
      # exit 2 = block, might be expected
      FAIL=$((FAIL + 1))
      echo "❌ $desc (exit $code)"
    else
      FAIL=$((FAIL + 1))
      echo "❌ $desc (exit $code)"
    fi
  fi
}

run_test_blocked() {
  local desc="$1"; shift
  TOTAL=$((TOTAL + 1))
  local code=0
  "$@" 2>/dev/null || code=$?
  if [ "$code" -eq 2 ]; then
    PASS=$((PASS + 1))
    echo "✅ $desc (correctly blocked)"
  else
    FAIL=$((FAIL + 1))
    echo "❌ $desc (expected block, got exit $code)"
  fi
}

cleanup() {
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR"
}

# Test 1: First compaction should be allowed
cleanup
run_test "First compaction allowed" bash "$HOOK"

# Test 2: Second compaction within MIN_INTERVAL should be blocked (cooldown)
run_test_blocked "Cooldown blocks rapid compaction" bash "$HOOK"

# Test 3: After cooldown, compaction should be allowed
cleanup
echo "$(($(date +%s) - 200))" > "$STATE_FILE"
run_test "Compaction allowed after cooldown" bash "$HOOK"

# Test 4: Circuit breaker triggers after MAX_PER_HOUR
cleanup
NOW=$(date +%s)
for i in $(seq 1 3); do
  echo "$((NOW - 300 + i * 10))" >> "$STATE_FILE"
done
run_test_blocked "Circuit breaker blocks after 3 compactions" bash "$HOOK"

# Test 5: Old entries are cleaned up
cleanup
ONE_HOUR_AGO=$(($(date +%s) - 3700))
for i in $(seq 1 5); do
  echo "$((ONE_HOUR_AGO - i * 10))" >> "$STATE_FILE"
done
run_test "Old entries cleaned, compaction allowed" bash "$HOOK"

# Test 6: Custom MAX_PER_HOUR
cleanup
NOW=$(date +%s)
echo "$((NOW - 200))" > "$STATE_FILE"
run_test_blocked "Custom MAX_PER_HOUR=1 blocks second" env CC_COMPACT_MAX_PER_HOUR=1 bash "$HOOK"

# Test 7: Custom MIN_INTERVAL
cleanup
echo "$(date +%s)" > "$STATE_FILE"
run_test_blocked "Default MIN_INTERVAL blocks immediate retry" bash "$HOOK"

# Test 8: State directory created if missing
rm -rf "$STATE_DIR"
run_test "Creates state directory" bash "$HOOK"
[ -d "$STATE_DIR" ] && echo "  ↳ State directory exists ✅" || echo "  ↳ State directory missing ❌"

# Test 9: Empty state file handled
cleanup
mkdir -p "$STATE_DIR"
touch "$STATE_FILE"
run_test "Empty state file handled" bash "$HOOK"

# Test 10: Mixed old and new entries
cleanup
NOW=$(date +%s)
echo "$((NOW - 7200))" >> "$STATE_FILE"  # 2 hours ago (old)
echo "$((NOW - 7100))" >> "$STATE_FILE"  # old
echo "$((NOW - 200))" >> "$STATE_FILE"   # recent (1)
run_test "Mixed entries: old cleaned, recent counted" bash "$HOOK"

# Test 11: Exactly at MAX_PER_HOUR boundary
cleanup
NOW=$(date +%s)
echo "$((NOW - 1800))" >> "$STATE_FILE"
echo "$((NOW - 900))" >> "$STATE_FILE"
echo "$((NOW - 200))" >> "$STATE_FILE"
run_test_blocked "Exactly at MAX=3 boundary blocked" bash "$HOOK"

# Test 12: Error message content
cleanup
NOW=$(date +%s)
for i in $(seq 1 3); do
  echo "$((NOW - 300 + i * 10))" >> "$STATE_FILE"
done
OUTPUT=$(bash "$HOOK" 2>&1 || true)
TOTAL=$((TOTAL + 1))
if echo "$OUTPUT" | grep -q "CIRCUIT BREAKER"; then
  PASS=$((PASS + 1))
  echo "✅ Error message contains CIRCUIT BREAKER"
else
  FAIL=$((FAIL + 1))
  echo "❌ Error message missing CIRCUIT BREAKER: $OUTPUT"
fi

cleanup

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
