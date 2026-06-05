#!/bin/bash
# Tests for agent-view-quota-warn.sh and agent-view-quota-decrement.sh
WARN_HOOK="$(dirname "$0")/../examples/agent-view-quota-warn.sh"
DEC_HOOK="$(dirname "$0")/../examples/agent-view-quota-decrement.sh"
PASS=0 FAIL=0

# Test session isolation
TEST_SESSION="test-$$-$RANDOM"
COUNTER_FILE="/tmp/cc-agent-view-tasks-${TEST_SESSION}"
cleanup() { rm -f "$COUNTER_FILE" "/tmp/cc-agent-view-tasks-ppid-$$" "/tmp/cc-agent-view-tasks-ppid-unknown"; }
trap cleanup EXIT

run_warn() {
  local input="$1"
  shift
  echo "$input" | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" "$@" bash "$WARN_HOOK" 2>/tmp/warn-stderr
  return $?
}

run_dec() {
  local input="$1"
  echo "$input" | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$DEC_HOOK" 2>/dev/null
  return $?
}

assert_count() {
  local expected="$1" desc="$2"
  local actual
  actual=$(cat "$COUNTER_FILE" 2>/dev/null || echo "MISSING")
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc (count=$actual)"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected count=$expected, got $actual)"
    ((FAIL++))
  fi
}

assert_exit() {
  local expected="$1" actual="$2" desc="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $desc (exit=$actual)"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit=$expected, got $actual)"
    ((FAIL++))
  fi
}

assert_stderr_contains() {
  local needle="$1" desc="$2"
  if grep -q "$needle" /tmp/warn-stderr 2>/dev/null; then
    echo "  PASS: $desc (stderr contains '$needle')"
    ((PASS++))
  else
    echo "  FAIL: $desc (stderr does not contain '$needle')"
    echo "    stderr was: $(cat /tmp/warn-stderr 2>/dev/null || echo 'EMPTY')"
    ((FAIL++))
  fi
}

assert_stderr_empty() {
  local desc="$1"
  if [ ! -s /tmp/warn-stderr ]; then
    echo "  PASS: $desc (stderr empty)"
    ((PASS++))
  else
    echo "  FAIL: $desc (stderr non-empty)"
    echo "    stderr: $(cat /tmp/warn-stderr 2>/dev/null)"
    ((FAIL++))
  fi
}

echo "Testing agent-view-quota-warn.sh + decrement"
echo "==========================================="

# Reset counter for tests
rm -f "$COUNTER_FILE"

# 1. Non-Task tool input should pass without affecting counter
run_warn '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_exit 0 $? "non-Task tool exits 0"
[ ! -f "$COUNTER_FILE" ] && { echo "  PASS: non-Task does not create counter"; ((PASS++)); } || { echo "  FAIL: non-Task created counter"; ((FAIL++)); }

# 2. First Task spawn increments to 1, no warning
run_warn '{"tool_name":"Task","tool_input":{"description":"do thing"}}'
assert_exit 0 $? "first Task exits 0"
assert_count 1 "first Task increments to 1"
assert_stderr_empty "first Task is silent (below threshold)"

# 3. Second Task increments to 2, still below default threshold (3)
run_warn '{"tool_name":"Task","tool_input":{"description":"do thing 2"}}'
assert_count 2 "second Task increments to 2"
assert_stderr_empty "second Task is silent (below threshold 3)"

# 4. Third Task hits threshold, warning emitted
run_warn '{"tool_name":"Task","tool_input":{"description":"do thing 3"}}'
assert_count 3 "third Task increments to 3"
assert_stderr_contains "concurrent Tasks tracked" "third Task triggers threshold warning"

# 5. Decrement on PostToolUse Task
run_dec '{"tool_name":"Task","tool_input":{"description":"done 1"}}'
assert_exit 0 $? "decrement exits 0"
assert_count 2 "decrement brings count to 2"

# 6. Decrement twice brings to 0
run_dec '{"tool_name":"Task","tool_input":{}}'
run_dec '{"tool_name":"Task","tool_input":{}}'
assert_count 0 "two more decrements bring to 0"

# 7. Decrement at 0 stays at 0 (no negative)
run_dec '{"tool_name":"Task","tool_input":{}}'
assert_count 0 "decrement at 0 stays at 0 (clamped)"

# 8. Reset, climb to 10 to trigger PEAK warning
rm -f "$COUNTER_FILE"
for i in 1 2 3 4 5 6 7 8 9; do
  echo '{"tool_name":"Task","tool_input":{}}' | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" 2>/dev/null
done
run_warn '{"tool_name":"Task","tool_input":{}}'
assert_count 10 "ten Tasks tracked"
assert_stderr_contains "PEAK" "tenth Task triggers PEAK warning"
assert_stderr_contains "1/10th" "PEAK message includes burn ratio"

# 9. CC_AGENT_VIEW_QUIET=1 suppresses warnings
rm -f "$COUNTER_FILE"
for i in 1 2 3 4 5; do
  echo '{"tool_name":"Task","tool_input":{}}' | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" 2>/dev/null
done
echo '{"tool_name":"Task","tool_input":{}}' | env CC_AGENT_VIEW_QUIET=1 CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" 2>/tmp/warn-stderr
assert_stderr_empty "CC_AGENT_VIEW_QUIET=1 suppresses warnings"

# 10. Custom threshold via env
rm -f "$COUNTER_FILE"
echo '{"tool_name":"Task","tool_input":{}}' | env CC_AGENT_VIEW_WARN_THRESHOLD=1 CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" 2>/tmp/warn-stderr
assert_stderr_contains "concurrent Tasks tracked" "threshold=1 triggers on first Task"

# 11. Corrupted counter file recovers to 1 on next increment
rm -f "$COUNTER_FILE"
echo "garbage" > "$COUNTER_FILE"
run_warn '{"tool_name":"Task","tool_input":{}}'
assert_count 1 "corrupted counter recovers to 1"

# 12. Missing CLAUDE_CODE_SESSION_ID falls back to PPID
rm -f /tmp/cc-agent-view-tasks-ppid-*
echo '{"tool_name":"Task","tool_input":{}}' | env -u CLAUDE_CODE_SESSION_ID bash "$WARN_HOOK" 2>/dev/null
# PPID will be the shell PID; just check that SOME counter file was created
if ls /tmp/cc-agent-view-tasks-ppid-* >/dev/null 2>&1; then
  echo "  PASS: PPID fallback creates counter"
  ((PASS++))
  rm -f /tmp/cc-agent-view-tasks-ppid-*
else
  echo "  FAIL: PPID fallback did not create counter"
  ((FAIL++))
fi

# 13. Empty input does not crash
echo "" | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" 2>/dev/null
assert_exit 0 $? "empty input exits 0"

# 14. Non-JSON input does not crash
echo "not json" | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" 2>/dev/null
assert_exit 0 $? "non-JSON input exits 0"

# 15. Hook never blocks (always exit 0 advisory)
rm -f "$COUNTER_FILE"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  echo '{"tool_name":"Task","tool_input":{}}' | env CLAUDE_CODE_SESSION_ID="$TEST_SESSION" bash "$WARN_HOOK" >/dev/null 2>/dev/null
  ec=$?
  if [ "$ec" -ne 0 ]; then
    echo "  FAIL: hook exited non-zero at iteration $i (got $ec)"
    ((FAIL++))
    break
  fi
done
if [ "$i" = "12" ]; then
  echo "  PASS: hook always exits 0 across 12 increments (never blocks)"
  ((PASS++))
fi

echo ""
echo "==========================================="
echo "RESULTS: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
