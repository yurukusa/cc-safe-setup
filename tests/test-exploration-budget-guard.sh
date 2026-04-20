#!/bin/bash
# Tests for exploration-budget-guard.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/exploration-budget-guard.sh"
PASS=0
FAIL=0
STATE_FILE="/tmp/.cc-exploration-budget/exploration-count"

setup() {
    rm -f "$STATE_FILE"
    mkdir -p /tmp/.cc-exploration-budget
}

run_hook() {
    echo "$1" | bash "$HOOK" 2>&1 || true
}

assert_pass() {
    local desc="$1"
    local input="$2"
    output=$(echo "$input" | bash "$HOOK" 2>&1) && rc=0 || rc=$?
    if [ "$rc" -eq 0 ] && ! echo "$output" | grep -q "WARNING\|BLOCKED"; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc (expected clean pass, rc=$rc)"
        echo "    output: $output"
    fi
}

assert_warn() {
    local desc="$1"
    local input="$2"
    output=$(echo "$input" | bash "$HOOK" 2>&1) && rc=0 || rc=$?
    if [ $rc -eq 0 ] && echo "$output" | grep -q "WARNING"; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc (expected warning, rc=$rc)"
        echo "    output: $output"
    fi
}

assert_block() {
    local desc="$1"
    local input="$2"
    output=$(echo "$input" | bash "$HOOK" 2>&1) && rc=0 || rc=$?
    if [ $rc -eq 2 ] && echo "$output" | grep -q "BLOCKED"; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc (expected block, rc=$rc)"
        echo "    output: $output"
    fi
}

READ_INPUT='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
GLOB_INPUT='{"tool_name":"Glob","tool_input":{"pattern":"*.ts"}}'
GREP_INPUT='{"tool_name":"Grep","tool_input":{"pattern":"foo"}}'
EDIT_INPUT='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.txt","old_string":"a","new_string":"b"}}'
WRITE_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.txt","content":"hello"}}'
OTHER_INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}'

echo "=== exploration-budget-guard tests ==="

# Test 1: Single read passes
setup
assert_pass "single Read passes" "$READ_INPUT"

# Test 2: Non-tracked tool passes
setup
assert_pass "Bash is not tracked" "$OTHER_INPUT"

# Test 3: Edit resets counter
setup
for i in $(seq 1 20); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
echo "$EDIT_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
assert_pass "Read after Edit reset passes" "$READ_INPUT"

# Test 4: Write resets counter
setup
for i in $(seq 1 20); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
echo "$WRITE_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
assert_pass "Read after Write reset passes" "$READ_INPUT"

# Test 5: Warning at threshold
setup
for i in $(seq 1 24); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
assert_warn "warns at 25 reads" "$READ_INPUT"

# Test 6: Different read tools count together
setup
for i in $(seq 1 8); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
    echo "$GLOB_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
    echo "$GREP_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
assert_warn "mixed read tools warn at 25" "$READ_INPUT"

# Test 7: Block at 40
setup
for i in $(seq 1 39); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
assert_block "blocks at 40 reads" "$READ_INPUT"

# Test 8: Block shows count
setup
for i in $(seq 1 41); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
output=$(echo "$READ_INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "EXCEEDED"; then
    PASS=$((PASS + 1))
    echo "  PASS: block message shows EXCEEDED"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: block message should show EXCEEDED"
fi

# Test 9: Timeout reset (simulate 11 min gap)
setup
for i in $(seq 1 30); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
# Fake old timestamp
echo "30 $(($(date +%s) - 700))" > "$STATE_FILE"
assert_pass "resets after 10min gap" "$READ_INPUT"

# Test 10: Glob passes normally
setup
assert_pass "single Glob passes" "$GLOB_INPUT"

# Test 11: Grep passes normally
setup
assert_pass "single Grep passes" "$GREP_INPUT"

# Test 12: Counter persists across different read tools
setup
for i in $(seq 1 10); do
    echo "$READ_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
for i in $(seq 1 10); do
    echo "$GLOB_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
for i in $(seq 1 5); do
    echo "$GREP_INPUT" | bash "$HOOK" >/dev/null 2>&1 || true
done
# Count should be 25 now
assert_warn "warns at 25 mixed reads" "$GREP_INPUT"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
