#!/bin/bash
# Tests for model-version-change-alert.sh
HOOK="examples/model-version-change-alert.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

HISTORY="/tmp/cc-model-version-history"
rm -f "$HISTORY"

# Test 1: First run (no history) — no alert
OUT=$(CLAUDE_MODEL="opus-4.7" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "first run should not alert" "$OUT" "MODEL CHANGED"
assert_exit "first run exit 0" "$RC" 0

# Test 2: Same model — no alert
OUT=$(CLAUDE_MODEL="opus-4.7" bash "$HOOK" 2>&1)
assert_not_contains "same model no alert" "$OUT" "MODEL CHANGED"

# Test 3: Model changed — should alert
OUT=$(CLAUDE_MODEL="opus-4.6" bash "$HOOK" 2>&1)
assert_contains "model change should alert" "$OUT" "MODEL CHANGED"
assert_contains "should show old model" "$OUT" "opus-4.7"
assert_contains "should show new model" "$OUT" "opus-4.6"
assert_contains "should reference issue" "$OUT" "#49689"

# Test 4: Exit code always 0
RC=$?
assert_exit "exit 0 on alert" "$RC" 0

# Test 5: Unknown model — no update, no alert
echo "opus-4.7" > "$HISTORY"
OUT=$(bash "$HOOK" 2>&1)  # No CLAUDE_MODEL set
assert_not_contains "unknown model no alert" "$OUT" "MODEL CHANGED"

# Test 6: History file is updated correctly
echo "opus-4.6" > "$HISTORY"
CLAUDE_MODEL="opus-4.7" bash "$HOOK" > /dev/null 2>&1
STORED=$(cat "$HISTORY")
if [ "$STORED" = "opus-4.7" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: history should store new model (got $STORED)"; fi

# Test 7: Back-to-back changes detected
CLAUDE_MODEL="sonnet-4.5" bash "$HOOK" > /dev/null 2>&1
OUT=$(CLAUDE_MODEL="haiku-4.5" bash "$HOOK" 2>&1)
assert_contains "sequential change detected" "$OUT" "MODEL CHANGED"
assert_contains "shows sonnet" "$OUT" "sonnet-4.5"

# Cleanup
rm -f "$HISTORY"

echo "model-version-change-alert: $PASS passed, $FAIL failed"
exit $FAIL
