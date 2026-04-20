#!/bin/bash
# Tests for tool-retry-budget-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/tool-retry-budget-guard.sh"

# Clean state before tests
rm -rf /tmp/.cc-retry-budget

test_hook() {
    local input="$1" expected_exit="$2" desc="$3"
    local actual_exit=0
    echo "$input" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "tool-retry-budget-guard.sh tests"
echo ""

# Clean state
rm -rf /tmp/.cc-retry-budget

# --- Allow: First few edits ---
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Allow 1st edit to file A"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Allow 2nd edit to file A"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Allow 3rd edit to file A"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Allow 4th edit to file A"

# --- Allow: Warning at 5th (exit 0 but with warning) ---
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Warn at 5th edit (still allow)"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Warn at 6th edit (still allow)"

# --- Block: 7th attempt ---
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 2 "Block at 7th consecutive edit"

# --- After block, counter resets ---
rm -rf /tmp/.cc-retry-budget
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-a.txt"}}' 0 "Allow after counter reset"

# --- Different files don't interfere ---
rm -rf /tmp/.cc-retry-budget
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-b.txt"}}' 0 "Allow edit to file B"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-c.txt"}}' 0 "Allow edit to file C"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test-retry-b.txt"}}' 0 "Allow 2nd edit to file B"

# --- Write tool also tracked ---
rm -rf /tmp/.cc-retry-budget
for i in $(seq 1 6); do
    test_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test-retry-w.txt"}}' 0 "Write attempt $i (allow)"
done
test_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test-retry-w.txt"}}' 2 "Block Write at 7th attempt"

# --- Non-Edit/Write tools pass through ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0 "Allow Bash (not tracked)"
test_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' 0 "Allow Read (not tracked)"
test_hook '{"tool_name":"Grep","tool_input":{"pattern":"test"}}' 0 "Allow Grep (not tracked)"

# --- Empty input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_name":"Edit","tool_input":{}}' 0 "Allow Edit with no file_path"

# Clean up
rm -rf /tmp/.cc-retry-budget

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
