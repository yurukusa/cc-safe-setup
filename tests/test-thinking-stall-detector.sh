#!/bin/bash
# Tests for thinking-stall-detector.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/thinking-stall-detector.sh"
PASS=0
FAIL=0
STATE_FILE="/tmp/cc-thinking-stall-last-call"
LOG_FILE="/tmp/cc-thinking-stalls.log"

setup() {
    rm -f "$STATE_FILE" "$LOG_FILE"
}

run_hook() {
    echo "$1" | CC_STALL_WARN_SECS="${2:-300}" bash "$HOOK" 2>&1 || true
}

# --- Test 1: First call (no previous state) should not warn ---
setup
output=$(echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=300 bash "$HOOK" 2>&1) || true
if echo "$output" | grep -q "stall"; then
    echo "  FAIL: first call should not warn"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: first call does not warn"
    PASS=$((PASS + 1))
fi

# --- Test 2: Quick successive calls should not warn ---
setup
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=300 bash "$HOOK" 2>/dev/null || true
sleep 1
output=$(echo '{"tool_name":"Write"}' | CC_STALL_WARN_SECS=300 bash "$HOOK" 2>&1) || true
if echo "$output" | grep -q "stall"; then
    echo "  FAIL: quick succession should not warn"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: quick succession does not warn"
    PASS=$((PASS + 1))
fi

# --- Test 3: Stall detected with low threshold ---
setup
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
sleep 2
output=$(echo '{"tool_name":"Bash"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>&1) || true
if echo "$output" | grep -qi "stall"; then
    echo "  PASS: stall detected after threshold"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should have detected stall after 2s with 1s threshold"
    echo "    output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Stall is logged to file ---
setup
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
sleep 2
echo '{"tool_name":"Edit"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
if [ -f "$LOG_FILE" ] && grep -q "STALL" "$LOG_FILE"; then
    echo "  PASS: stall logged to file"
    PASS=$((PASS + 1))
else
    echo "  FAIL: stall not logged to $LOG_FILE"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: Log contains tool name ---
if [ -f "$LOG_FILE" ] && grep -q "tool=Edit" "$LOG_FILE"; then
    echo "  PASS: log contains tool name"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log should contain tool=Edit"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Warning mentions issue number ---
setup
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
sleep 2
output=$(echo '{"tool_name":"Glob"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>&1) || true
if echo "$output" | grep -q "51092"; then
    echo "  PASS: warning references #51092"
    PASS=$((PASS + 1))
else
    echo "  FAIL: warning should reference #51092"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: After stall, next quick call should not warn ---
setup
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
sleep 2
echo '{"tool_name":"Edit"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
output=$(echo '{"tool_name":"Write"}' | CC_STALL_WARN_SECS=300 bash "$HOOK" 2>&1) || true
if echo "$output" | grep -q "stall"; then
    echo "  FAIL: should not warn on quick follow-up after stall"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: no false positive after stall recovery"
    PASS=$((PASS + 1))
fi

# --- Test 8: Hook always exits 0 (never blocks) ---
setup
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null || true
sleep 2
echo '{"tool_name":"Bash"}' | CC_STALL_WARN_SECS=1 bash "$HOOK" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  PASS: hook exits 0 (warn-only, never blocks)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook should always exit 0, got $rc"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: Empty tool name handled gracefully ---
setup
output=$(echo '{}' | CC_STALL_WARN_SECS=300 bash "$HOOK" 2>&1) || true
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  PASS: empty tool name handled"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should handle empty tool name gracefully"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: Custom log path ---
setup
CUSTOM_LOG="/tmp/cc-stall-custom-test.log"
rm -f "$CUSTOM_LOG"
echo '{"tool_name":"Read"}' | CC_STALL_WARN_SECS=1 CC_STALL_LOG="$CUSTOM_LOG" bash "$HOOK" 2>/dev/null || true
sleep 2
echo '{"tool_name":"Write"}' | CC_STALL_WARN_SECS=1 CC_STALL_LOG="$CUSTOM_LOG" bash "$HOOK" 2>/dev/null || true
if [ -f "$CUSTOM_LOG" ] && grep -q "STALL" "$CUSTOM_LOG"; then
    echo "  PASS: custom log path works"
    PASS=$((PASS + 1))
else
    echo "  FAIL: custom log path not working"
    FAIL=$((FAIL + 1))
fi
rm -f "$CUSTOM_LOG"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
