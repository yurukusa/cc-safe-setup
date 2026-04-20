#!/bin/bash
# Tests for read-once-guard.sh
HOOK="$(dirname "$0")/../examples/read-once-guard.sh"
PASS=0 FAIL=0
TMPFILE="/tmp/test-read-once-$$"

setup() {
  rm -rf /tmp/cc-read-once
  echo "test content" > "$TMPFILE"
}

run_test() {
  local desc="$1" expected_exit="$2"
  shift 2
  local actual_exit
  echo "{\"tool_input\":{\"file_path\":\"$TMPFILE\"}}" | env "$@" bash "$HOOK" >/dev/null 2>/dev/null
  actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    ((FAIL++))
  fi
}

echo "Testing read-once-guard.sh"
echo "=========================="

# 1. First read always passes
setup
run_test "first read passes" 0 CC_READ_ONCE_MAX=3

# 2. Second read passes (under threshold)
run_test "second read passes" 0 CC_READ_ONCE_MAX=3

# 3. Third read passes (at threshold)
run_test "third read passes" 0 CC_READ_ONCE_MAX=3

# 4. Fourth read still passes in warn mode (exit 0)
run_test "fourth read warns but passes (warn mode)" 0 CC_READ_ONCE_ACTION=warn CC_READ_ONCE_MAX=3

# 5. Block mode blocks after threshold
setup
for i in 1 2 3; do
  echo "{\"tool_input\":{\"file_path\":\"$TMPFILE\"}}" | env CC_SESSION_ID=test-block CC_READ_ONCE_MAX=2 CC_READ_ONCE_ACTION=block bash "$HOOK" >/dev/null 2>/dev/null
done
run_test "block mode blocks after threshold" 2 CC_SESSION_ID=test-block CC_READ_ONCE_ACTION=block CC_READ_ONCE_MAX=2

# 6. File modification resets counter
setup
for i in 1 2 3; do
  echo "{\"tool_input\":{\"file_path\":\"$TMPFILE\"}}" | env CC_READ_ONCE_MAX=2 CC_READ_ONCE_ACTION=block bash "$HOOK" >/dev/null 2>/dev/null
done
sleep 1
echo "modified" > "$TMPFILE"  # Modify file
run_test "file modification resets counter" 0 CC_READ_ONCE_ACTION=block CC_READ_ONCE_MAX=2

# 7. Empty file_path passes
echo '{"tool_input":{}}' | bash "$HOOK" >/dev/null 2>/dev/null
if [ $? -eq 0 ]; then
  echo "  PASS: empty file_path passes"
  ((PASS++))
else
  echo "  FAIL: empty file_path should pass"
  ((FAIL++))
fi

# 8. Non-existent file passes (first read)
setup
echo '{"tool_input":{"file_path":"/tmp/nonexistent-test-file-xyz"}}' | bash "$HOOK" >/dev/null 2>/dev/null
if [ $? -eq 0 ]; then
  echo "  PASS: non-existent file passes"
  ((PASS++))
else
  echo "  FAIL: non-existent file should pass"
  ((FAIL++))
fi

# Cleanup
rm -f "$TMPFILE"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
