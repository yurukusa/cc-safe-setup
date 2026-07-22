#!/bin/bash
# Tests for warn-cron-cost-trap.sh
HOOK="examples/warn-cron-cost-trap.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if echo "$2" | grep -q "$3"; then FAIL=$((FAIL+1)); echo "FAIL: $1 (did not expect '$3')"; else PASS=$((PASS+1)); fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"
WARN="COST TRAP"

# Test 1: */5 recurring -> warns
OUT=$(echo '{"tool_input":{"cron":"*/5 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "step5 exit 0 (advisory)" "$RC" "0"
assert_contains "step5 warns" "$OUT" "$WARN"
assert_contains "step5 reports interval 5" "$OUT" "every 5 min"

# Test 2: the #74547 example 7,18,29,40,51 (min gap 11) recurring -> warns
OUT=$(echo '{"tool_input":{"cron":"7,18,29,40,51 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "list11 exit 0" "$RC" "0"
assert_contains "list11 warns" "$OUT" "$WARN"
assert_contains "list11 min gap 11" "$OUT" "every 11 min"

# Test 3: every minute -> warns with interval 1
OUT=$(echo '{"tool_input":{"cron":"* * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1)
assert_contains "everymin warns" "$OUT" "$WARN"
assert_contains "everymin interval 1" "$OUT" "every 1 min"

# Test 4: hourly 0 * * * * recurring -> safe, no warn
OUT=$(echo '{"tool_input":{"cron":"0 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "hourly exit 0" "$RC" "0"
assert_not_contains "hourly no warn" "$OUT" "$WARN"

# Test 5: */20 (above default threshold 15) recurring -> no warn
OUT=$(echo '{"tool_input":{"cron":"*/20 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1)
assert_not_contains "step20 no warn" "$OUT" "$WARN"

# Test 6: short interval but recurring=false (one-shot) -> no warn
OUT=$(echo '{"tool_input":{"cron":"*/5 * * * *","recurring":false}}' | bash "$HOOK_ABS" 2>&1)
assert_not_contains "oneshot no warn" "$OUT" "$WARN"

# Test 6b: short interval with recurring OMITTED -> CronCreate defaults to
# recurring, so this most-dangerous form must still warn (regression guard
# for the `recurring // false` default-direction bug).
OUT=$(echo '{"tool_input":{"cron":"*/5 * * * *"}}' | bash "$HOOK_ABS" 2>&1)
assert_contains "omitted recurring warns" "$OUT" "$WARN"
assert_contains "omitted interval 5" "$OUT" "every 5 min"

# Test 7: comma list with a small gap anywhere (0,1,30) -> min gap 1 -> warns
OUT=$(echo '{"tool_input":{"cron":"0,1,30 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1)
assert_contains "list gap1 warns" "$OUT" "$WARN"

# Test 8: wraparound gap (55,5 -> gap 10 via wrap) recurring -> warns
OUT=$(echo '{"tool_input":{"cron":"5,55 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1)
assert_contains "wrap gap10 warns" "$OUT" "$WARN"

# Test 9: single minute value (30 * * * *) recurring -> hourly -> no warn
OUT=$(echo '{"tool_input":{"cron":"30 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1)
assert_not_contains "single no warn" "$OUT" "$WARN"

# Test 9b: minute-field range without step (0-30) fires every minute -> warns interval 1
OUT=$(echo '{"tool_input":{"cron":"0-30 * * * *","recurring":true}}' | bash "$HOOK_ABS" 2>&1)
assert_contains "range warns" "$OUT" "$WARN"
assert_contains "range interval 1" "$OUT" "every 1 min"

# Test 10: no cron field -> exit 0, no warn
OUT=$(echo '{"tool_input":{}}' | bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "nocron exit 0" "$RC" "0"
assert_not_contains "nocron no warn" "$OUT" "$WARN"

# Test 11: disable env var suppresses warning
OUT=$(echo '{"tool_input":{"cron":"*/5 * * * *","recurring":true}}' | CC_CRON_COST_TRAP_DISABLE=1 bash "$HOOK_ABS" 2>&1)
assert_not_contains "disabled no warn" "$OUT" "$WARN"

# Test 12: custom threshold — */20 with threshold 30 warns
OUT=$(echo '{"tool_input":{"cron":"*/20 * * * *","recurring":true}}' | CC_CRON_COST_TRAP_THRESHOLD_MIN=30 bash "$HOOK_ABS" 2>&1)
assert_contains "custom threshold warns" "$OUT" "$WARN"

echo ""
echo "warn-cron-cost-trap: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
