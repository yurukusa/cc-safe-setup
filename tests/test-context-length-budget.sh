#!/bin/bash
# Tests for context-length-budget.sh
HOOK="examples/context-length-budget.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"

# Test 1: Under threshold → no warning, log written
SESS="ctx-test-$(date +%s%N)-1"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{"input_tokens":5000,"cache_read_input_tokens":10000,"cache_creation_input_tokens":1000}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "under threshold exits 0" "$RC" 0
assert_not_contains "under threshold no warning" "$OUT" "context-length-budget"
if [ -s "$LOG_DIR/context-budget-$SESS.log" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: log should be written"; fi
if grep -q "16000" "$LOG_DIR/context-budget-$SESS.log"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: cumulative 16000 should be logged"; fi
rm -f "$TRANS" "$LOG_DIR/context-budget-$SESS".*

# Test 2: Over threshold → warning once
SESS="ctx-test-$(date +%s%N)-2"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{"input_tokens":100000,"cache_read_input_tokens":150000,"cache_creation_input_tokens":1000}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
assert_contains "over threshold warns" "$OUT" "context-length-budget"
assert_contains "warning shows cumulative" "$OUT" "251000"
assert_contains "warning references MRCR" "$OUT" "MRCR"

# Test 3: Second turn over threshold → no duplicate warning (sentinel)
OUT2=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
assert_not_contains "already-warned session stays silent" "$OUT2" "context-length-budget"
rm -f "$TRANS" "$LOG_DIR/context-budget-$SESS".*

# Test 4: Custom threshold respected
SESS="ctx-test-$(date +%s%N)-4"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{"input_tokens":50000,"cache_read_input_tokens":20000,"cache_creation_input_tokens":0}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | CONTEXT_BUDGET_THRESHOLD=50000 bash "$HOOK" 2>&1)
assert_contains "custom threshold triggers at 70000 > 50000" "$OUT" "context-length-budget"
rm -f "$TRANS" "$LOG_DIR/context-budget-$SESS".*

# Test 5: No transcript → silent no-op
OUT=$(printf '{"session_id":"no-trans","tool_name":"x"}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no transcript exits 0" "$RC" 0
assert_not_contains "no transcript no warning" "$OUT" "context-length-budget"

# Test 6: Missing session_id → no-op
OUT=$(printf '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing session_id exits 0" "$RC" 0

# Test 7: Usage fields missing → cumulative 0 logged, no warning
SESS="ctx-test-$(date +%s%N)-7"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
assert_not_contains "empty usage no warning" "$OUT" "context-length-budget"
rm -f "$TRANS" "$LOG_DIR/context-budget-$SESS".*

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
