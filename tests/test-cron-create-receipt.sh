#!/bin/bash
# Tests for cron-create-receipt.sh
HOOK="$(dirname "$0")/../examples/cron-create-receipt.sh"
PASS=0 FAIL=0

# Use an isolated state directory per test run so tests do not pollute
# the user's actual ~/.claude/state/crons/registered/.
TEST_STATE_DIR=$(mktemp -d -t cron-receipt-test-XXXXXX)
trap 'rm -rf "$TEST_STATE_DIR"' EXIT

count_receipts() {
  find "$TEST_STATE_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

clear_receipts() {
  rm -rf "$TEST_STATE_DIR"/* 2>/dev/null || true
}

run_test() {
  local desc="$1" expected_exit="$2" input="$3"
  shift 3
  local actual_exit
  printf '%s' "$input" | env CC_CRON_RECEIPT_DIR="$TEST_STATE_DIR" "$@" bash "$HOOK" >/dev/null 2>/dev/null
  actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL+1))
  fi
}

assert_receipt_count() {
  local desc="$1" expected_count="$2"
  local actual_count
  actual_count=$(count_receipts)
  if [ "$actual_count" -eq "$expected_count" ]; then
    echo "  PASS: $desc (count=$actual_count)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected count=$expected_count, got $actual_count)"
    FAIL=$((FAIL+1))
  fi
}

assert_receipt_field() {
  local desc="$1" jq_path="$2" expected="$3"
  local latest_file actual
  latest_file=$(find "$TEST_STATE_DIR" -name '*.json' | sort | tail -1)
  if [ -z "$latest_file" ]; then
    echo "  FAIL: $desc (no receipt file found)"
    FAIL=$((FAIL+1))
    return
  fi
  actual=$(jq -r "$jq_path" "$latest_file" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc ($jq_path=$actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected $jq_path=$expected, got $actual)"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing cron-create-receipt.sh"
echo "==============================="

# 1. Basic CronCreate registration produces a receipt
clear_receipts
run_test "basic CronCreate exits 0" 0 \
  '{"tool_name":"CronCreate","tool_input":{"cron":"40 * * * *","prompt":"check health","recurring":true},"tool_result":"Registered cron_id=abc123"}'
assert_receipt_count "basic registration produces 1 receipt" 1

# 2. Receipt contains the cron expression
assert_receipt_field "receipt records the cron expression" '.cron_expression' '40 * * * *'

# 3. Receipt contains the recurring flag (boolean)
assert_receipt_field "receipt records recurring=true" '.recurring' 'true'

# 4. Receipt contains a prompt excerpt
assert_receipt_field "receipt records prompt excerpt" '.prompt_excerpt' 'check health'

# 5. Long prompt is truncated to the excerpt length (default 200)
clear_receipts
LONG_PROMPT=$(printf 'x%.0s' {1..500})
run_test "long prompt exits 0" 0 \
  "{\"tool_name\":\"CronCreate\",\"tool_input\":{\"cron\":\"0 * * * *\",\"prompt\":\"$LONG_PROMPT\",\"recurring\":false},\"tool_result\":\"OK\"}"
LATEST=$(find "$TEST_STATE_DIR" -name '*.json' | sort | tail -1)
EXCERPT_LEN=$(jq -r '.prompt_excerpt' "$LATEST" | wc -c | tr -d ' ')
# jq -r adds a trailing newline so wc -c reports excerpt_len + 1
if [ "$EXCERPT_LEN" -le 201 ] && [ "$EXCERPT_LEN" -ge 200 ]; then
  echo "  PASS: long prompt truncated to ~200 chars (got $((EXCERPT_LEN - 1)))"
  PASS=$((PASS+1))
else
  echo "  FAIL: long prompt not truncated correctly (got $((EXCERPT_LEN - 1)) chars)"
  FAIL=$((FAIL+1))
fi

# 6. Custom excerpt length is respected
clear_receipts
run_test "custom excerpt length exits 0" 0 \
  '{"tool_name":"CronCreate","tool_input":{"cron":"5 * * * *","prompt":"abcdefghij","recurring":false},"tool_result":"OK"}' \
  CC_CRON_RECEIPT_EXCERPT_LEN=5
assert_receipt_field "custom excerpt length truncates" '.prompt_excerpt' 'abcde'

# 7. Disable flag skips the hook entirely (no receipt written)
clear_receipts
run_test "disabled hook exits 0" 0 \
  '{"tool_name":"CronCreate","tool_input":{"cron":"0 * * * *","prompt":"x","recurring":false},"tool_result":"OK"}' \
  CC_CRON_RECEIPT_DISABLE=1
assert_receipt_count "disabled hook writes no receipt" 0

# 8. Missing cron field exits silently (defensive)
clear_receipts
run_test "missing cron field exits 0" 0 \
  '{"tool_name":"CronCreate","tool_input":{"prompt":"x"},"tool_result":"OK"}'
assert_receipt_count "missing cron field writes no receipt" 0

# 9. Empty input exits silently (defensive)
clear_receipts
run_test "empty input exits 0" 0 ''
assert_receipt_count "empty input writes no receipt" 0

# 10. Malformed JSON exits silently (defensive)
clear_receipts
run_test "malformed JSON exits 0" 0 'not valid json at all'
assert_receipt_count "malformed JSON writes no receipt" 0

# 11. Multiple CronCreate calls each produce a separate receipt
clear_receipts
for i in 1 2 3; do
  printf '%s' "{\"tool_name\":\"CronCreate\",\"tool_input\":{\"cron\":\"$i * * * *\",\"prompt\":\"job$i\",\"recurring\":false},\"tool_result\":\"OK\"}" | \
    env CC_CRON_RECEIPT_DIR="$TEST_STATE_DIR" bash "$HOOK" >/dev/null 2>/dev/null
  # Sleep briefly so timestamps differ and filenames are unique
  sleep 1
done
assert_receipt_count "three CronCreate calls produce three receipts" 3

# 12. Recurring=false is recorded correctly
clear_receipts
run_test "one-shot cron exits 0" 0 \
  '{"tool_name":"CronCreate","tool_input":{"cron":"0 12 * * *","prompt":"daily","recurring":false},"tool_result":"OK"}'
assert_receipt_field "recurring=false recorded as boolean" '.recurring' 'false'

# 13. Receipt directory respects custom override
CUSTOM_DIR=$(mktemp -d -t cron-receipt-custom-XXXXXX)
trap "rm -rf '$TEST_STATE_DIR' '$CUSTOM_DIR'" EXIT
printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"0 * * * *","prompt":"x","recurring":false},"tool_result":"OK"}' | \
  env CC_CRON_RECEIPT_DIR="$CUSTOM_DIR" bash "$HOOK" >/dev/null 2>/dev/null
CUSTOM_COUNT=$(find "$CUSTOM_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$CUSTOM_COUNT" -eq 1 ]; then
  echo "  PASS: custom CC_CRON_RECEIPT_DIR is respected (count=1)"
  PASS=$((PASS+1))
else
  echo "  FAIL: custom CC_CRON_RECEIPT_DIR not respected (got count=$CUSTOM_COUNT)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
