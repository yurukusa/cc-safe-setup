#!/bin/bash
# Tests for temporal-suggestion-detector.sh
#
# Verifies the Stop-hook behavior for the temporal-disorientation pattern:
#   - Matching phrase → logs to disk, exit 0 (advisory by default)
#   - Matching phrase + STRICT mode → exit 2, stderr feedback, logged
#   - Non-matching phrase → exit 0 silent, no log
#   - Empty assistant text → exit 0 silent
#   - Disable flag respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/temporal-suggestion-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Isolated log file per test run
LOG_FILE=$(mktemp -t temporal-test-XXXXXX.log 2>/dev/null || mktemp /tmp/temporal-test-XXXXXX.log)
export CC_TEMPORAL_LOG="$LOG_FILE"

echo "=== temporal-suggestion-detector.sh tests ==="

# --- Test 1: matching phrase in advisory mode → exit 0, logged ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{
    transcript: [{content: "Great work today. You should go get some rest now."}],
    session_id: "test-session-1"
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ] && [ -s "$LOG_FILE" ]; then
    assert_pass "advisory mode: exit 0 silent, log written"
else
    log_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    assert_fail "expected exit 0 silent + non-empty log, got rc=$rc output='$output' log_size=$log_size"
fi

# --- Test 2: matching phrase content was captured correctly ---
if grep -q "test-session-1" "$LOG_FILE" && grep -qi "rest" "$LOG_FILE"; then
    assert_pass "log contains session_id and matched phrase"
else
    assert_fail "log missing session_id or matched phrase: $(cat "$LOG_FILE")"
fi

# --- Test 3: matching phrase in STRICT mode → exit 2 with feedback ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{
    transcript: [{content: "Good progress. Let us call it a day."}],
    session_id: "test-session-2"
}')
output=$(CC_TEMPORAL_STRICT=1 printf '%s' "$INPUT" | CC_TEMPORAL_STRICT=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "TEMPORAL SUGGESTION DETECTED"; then
    assert_pass "strict mode: exit 2 with feedback"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc output='$output'"
fi

# --- Test 4: no matching phrase → exit 0 silent, no log ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{
    transcript: [{content: "Investigating the failing test now. Re-running pytest."}],
    session_id: "test-session-3"
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ] && [ ! -s "$LOG_FILE" ]; then
    assert_pass "no match: exit 0 silent, log empty"
else
    log_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    assert_fail "expected exit 0 silent + empty log, got rc=$rc output='$output' log_size=$log_size"
fi

# --- Test 5: empty assistant text → exit 0 silent ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{transcript: [{content: ""}], session_id: "test-session-4"}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ] && [ ! -s "$LOG_FILE" ]; then
    assert_pass "empty text: exit 0 silent, no log"
else
    assert_fail "expected exit 0 silent + empty log, got rc=$rc"
fi

# --- Test 6: disable flag respected ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{transcript: [{content: "You should go to sleep now."}], session_id: "test-session-5"}')
output=$(CC_TEMPORAL_DETECT_DISABLE=1 bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$LOG_FILE" ]; then
    assert_pass "disable flag: exit 0, no log written"
else
    assert_fail "expected disabled (no log), got rc=$rc log_size=$(wc -c < "$LOG_FILE")"
fi

# --- Test 7: missing assistant text key → exit 0 silent ---
: > "$LOG_FILE"
INPUT='{"unknown_key": "value"}'
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ] && [ ! -s "$LOG_FILE" ]; then
    assert_pass "unknown harness shape: exit 0 silent (no false positive)"
else
    assert_fail "expected silent exit 0, got rc=$rc output='$output'"
fi

# --- Test 8: empty input → exit 0 silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input: exit 0 silent"
else
    assert_fail "expected silent exit 0, got rc=$rc output='$output'"
fi

# --- Test 9: array-form content (modern shape) ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{
    transcript: [{message: {content: [{type: "text", text: "All done. Now go get some rest."}]}}],
    session_id: "test-session-6"
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -s "$LOG_FILE" ] && grep -q "test-session-6" "$LOG_FILE"; then
    assert_pass "array-form content: detected and logged"
else
    log_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    assert_fail "expected detected+logged, got rc=$rc log_size=$log_size"
fi

# --- Test 10: multiple matching phrases in one turn ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{
    transcript: [{content: "Good progress! Time to take a break and get some rest."}],
    session_id: "test-session-7"
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
log_line=$(tail -1 "$LOG_FILE" 2>/dev/null || echo "")
if [ "$rc" -eq 0 ] && [ -s "$LOG_FILE" ] && echo "$log_line" | grep -q "|"; then
    assert_pass "multiple phrases in turn: captured with pipe separator"
else
    assert_fail "expected multi-match log entry, got rc=$rc log_line='$log_line'"
fi

# --- Test 11: custom log path respected ---
: > "$LOG_FILE"
CUSTOM_LOG=$(mktemp -t temporal-custom-XXXXXX.log 2>/dev/null || mktemp /tmp/temporal-custom-XXXXXX.log)
INPUT=$(jq -nc '{transcript: [{content: "You should stop for the night."}], session_id: "test-session-8"}')
output=$(CC_TEMPORAL_LOG="$CUSTOM_LOG" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -s "$CUSTOM_LOG" ] && [ ! -s "$LOG_FILE" ]; then
    assert_pass "custom CC_TEMPORAL_LOG path respected"
else
    assert_fail "expected log at $CUSTOM_LOG, got rc=$rc custom_size=$(wc -c < "$CUSTOM_LOG") default_size=$(wc -c < "$LOG_FILE")"
fi
rm -f "$CUSTOM_LOG"

# --- Test 12: custom pattern respected (no false positive on default phrase) ---
: > "$LOG_FILE"
INPUT=$(jq -nc '{transcript: [{content: "You should go get some rest."}], session_id: "test-session-9"}')
# Custom pattern matches "kangaroo" only — default phrase should not trigger
output=$(CC_TEMPORAL_PATTERN='kangaroo' bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$LOG_FILE" ]; then
    assert_pass "custom pattern: default phrases ignored when pattern overridden"
else
    assert_fail "expected no match, got rc=$rc log_size=$(wc -c < "$LOG_FILE")"
fi

# --- Cleanup ---
rm -f "$LOG_FILE"

echo ""
echo "=== Result: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
