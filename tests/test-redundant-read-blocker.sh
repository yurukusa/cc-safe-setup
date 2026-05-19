#!/bin/bash
# Tests for redundant-read-blocker.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/redundant-read-blocker.sh"
PASS=0
FAIL=0
STATE_DIR="/tmp/cc-redundant-read-test-$$"
SESSION_ID="test-$$"
TMP_FILE="$STATE_DIR/sample.txt"

setup() {
    rm -rf "$STATE_DIR" 2>/dev/null || true
    mkdir -p "$STATE_DIR"
    echo "sample content" > "$TMP_FILE"
}

run_hook() {
    local file="$1"
    local input
    input=$(jq -nc \
        --arg sid "$SESSION_ID" \
        --arg fp "$file" \
        '{tool_name: "Read", session_id: $sid, tool_input: {file_path: $fp}}')
    printf '%s' "$input" \
        | CC_REDUNDANT_READ_STATE_DIR="$STATE_DIR" \
          CC_REDUNDANT_READ_THRESHOLD="${THRESHOLD:-1}" \
          CC_REDUNDANT_READ_STRICT="${STRICT:-0}" \
          bash "$HOOK" 2>&1
    return $?
}

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== redundant-read-blocker.sh tests ==="

# --- Test 1: First read is silent ---
setup
output=$(run_hook "$TMP_FILE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "first read is a silent no-op"
else
    assert_fail "expected silent first read (rc=$rc output=$output)"
fi

# --- Test 2: Second read of same file (unchanged) hits threshold and warns ---
setup
run_hook "$TMP_FILE" >/dev/null
output=$(run_hook "$TMP_FILE")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "REDUNDANT READ"; then
    assert_pass "second read of unchanged file emits warning (rc=0 by default)"
else
    assert_fail "expected warning on 2nd read (rc=$rc output=$output)"
fi

# --- Test 3: Strict mode exits 2 on second read ---
setup
STRICT=1 run_hook "$TMP_FILE" >/dev/null
output=$(STRICT=1 run_hook "$TMP_FILE")
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "REDUNDANT READ"; then
    assert_pass "strict mode exits 2 with warning"
else
    assert_fail "expected exit 2 in strict mode (rc=$rc)"
fi

# --- Test 4: Modified file is not redundant (mtime changed) ---
setup
run_hook "$TMP_FILE" >/dev/null
sleep 1
echo "modified" > "$TMP_FILE"   # changes mtime
output=$(run_hook "$TMP_FILE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "modified file is not flagged as redundant"
else
    assert_fail "modified file should pass (rc=$rc output=$output)"
fi

# --- Test 5: Different paths do not interfere ---
setup
OTHER="$STATE_DIR/other.txt"
echo "other content" > "$OTHER"
run_hook "$TMP_FILE" >/dev/null
output=$(run_hook "$OTHER")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "different paths don't trigger each other"
else
    assert_fail "different file should pass (rc=$rc output=$output)"
fi

# --- Test 6: Threshold raised to 3 lets two reads pass silently ---
setup
THRESHOLD=3 run_hook "$TMP_FILE" >/dev/null
output=$(THRESHOLD=3 run_hook "$TMP_FILE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "raising THRESHOLD lets extra reads through"
else
    assert_fail "with THRESHOLD=3, 2 reads should be silent (rc=$rc output=$output)"
fi

# --- Test 7: Non-Read tool calls are ignored ---
setup
input=$(jq -nc --arg sid "$SESSION_ID" '{tool_name: "Edit", session_id: $sid, tool_input: {file_path: "x"}}')
output=$(printf '%s' "$input" | CC_REDUNDANT_READ_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-Read tool calls are ignored"
else
    assert_fail "expected silent for Edit (rc=$rc output=$output)"
fi

# --- Test 8: Missing file_path is a silent no-op ---
setup
input=$(jq -nc --arg sid "$SESSION_ID" '{tool_name: "Read", session_id: $sid, tool_input: {}}')
output=$(printf '%s' "$input" | CC_REDUNDANT_READ_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing file_path is silent no-op"
else
    assert_fail "expected silent (rc=$rc output=$output)"
fi

# --- Test 9: Warning references #60283 ---
setup
run_hook "$TMP_FILE" >/dev/null
output=$(run_hook "$TMP_FILE")
if echo "$output" | grep -q "#60283"; then
    assert_pass "warning references #60283 for grounding"
else
    assert_fail "expected reference to #60283 in warning"
fi

# --- Test 10: Reads log respects WINDOW size ---
setup
THRESHOLD=99 run_hook "$STATE_DIR/a.txt" >/dev/null 2>&1
THRESHOLD=99 run_hook "$STATE_DIR/b.txt" >/dev/null 2>&1
THRESHOLD=99 run_hook "$STATE_DIR/c.txt" >/dev/null 2>&1
THRESHOLD=99 run_hook "$STATE_DIR/d.txt" >/dev/null 2>&1
log_lines=$(wc -l < "$STATE_DIR/$SESSION_ID/reads.log" 2>/dev/null || echo 0)
if [ "$log_lines" -le 20 ]; then
    assert_pass "reads log respects window size (lines: $log_lines <= 20)"
else
    assert_fail "log grew unbounded (lines: $log_lines)"
fi

rm -rf "$STATE_DIR" 2>/dev/null || true
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
