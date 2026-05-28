#!/bin/bash
# Tests for cowork-model-picker-advisor.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/cowork-model-picker-advisor.sh"
PASS=0
FAIL=0

INPUT='{"session_id":"test-picker"}'

run_hook_with_env() {
    env -i HOME="$HOME" PATH="$PATH" "$@" bash -c "echo '$INPUT' | bash '$HOOK' 2>&1" || true
}

# --- Test 1: Fires full warning when ANTHROPIC_MODEL is unset ---
output=$(run_hook_with_env)
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: warns when ANTHROPIC_MODEL is unset"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn when ANTHROPIC_MODEL is unset"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: Fires full warning when ANTHROPIC_MODEL contains [1m] ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: warns when ANTHROPIC_MODEL contains [1m]"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for [1m] variant"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: Fires for -1m suffix ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6-1m')
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: warns for -1m suffix"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for -1m suffix"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Confirmation line for standard model ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6')
if echo "$output" | grep -q "standard context"; then
    echo "  PASS: shows confirmation for standard model"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should show confirmation for standard model"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: CC_COWORK_MODEL_QUIET suppresses confirmation for safe model ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6' CC_COWORK_MODEL_QUIET=1)
if [ -z "$output" ]; then
    echo "  PASS: CC_COWORK_MODEL_QUIET suppresses confirmation"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent when QUIET set and model is safe: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: CC_COWORK_MODEL_QUIET does NOT suppress 1m warning ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]' CC_COWORK_MODEL_QUIET=1)
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: QUIET does not suppress 1m warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: 1m warning should fire even with QUIET set"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: References issue #62949 ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "#62949"; then
    echo "  PASS: references #62949"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference #62949"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: References related issues ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "#61869" && echo "$output" | grep -q "#62100" && echo "$output" | grep -q "#61692"; then
    echo "  PASS: references related issues #61869 #62100 #61692"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference all 3 related issues"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: Shows --model CLI workaround ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q -- "--model claude-sonnet-4-6"; then
    echo "  PASS: shows --model workaround"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should show --model workaround"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: Shows API error fragment for searchability ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "Usage credits required"; then
    echo "  PASS: shows API error fragment for searchability"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should show API error fragment"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: CC_COWORK_MODEL_FORCE_WARN always shows full warning ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6' CC_COWORK_MODEL_FORCE_WARN=1)
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: FORCE_WARN shows full warning even for safe model"
    PASS=$((PASS + 1))
else
    echo "  FAIL: FORCE_WARN should always show warning"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: Always exits 0 (advisory only) ---
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 when fires"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 13: Exits 0 for safe model ---
echo "$INPUT" | ANTHROPIC_MODEL='claude-haiku-4-5' bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 for safe model"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0 for safe model, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 14: Handles 'unset' in display ---
output=$(run_hook_with_env)
if echo "$output" | grep -q "unset"; then
    echo "  PASS: displays 'unset' when ANTHROPIC_MODEL not set"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should display 'unset' when env var missing"
    FAIL=$((FAIL + 1))
fi

# --- Test 15: Documents SessionStart trigger ---
if grep -q "TRIGGER: SessionStart" "$HOOK"; then
    echo "  PASS: documents SessionStart trigger"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should document SessionStart trigger"
    FAIL=$((FAIL + 1))
fi

# --- Test 16: Mentions Max plan context ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "Max"; then
    echo "  PASS: mentions Max plan context"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should mention Max plan context"
    FAIL=$((FAIL + 1))
fi

# --- Test 17: Distinguishes Cowork from CLI in advisory ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "CLI" && echo "$output" | grep -qi "Cowork"; then
    echo "  PASS: distinguishes Cowork vs CLI"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should distinguish Cowork vs CLI"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: Log file written when CC_COWORK_MODEL_LOG set ---
LOG_FILE=$(mktemp /tmp/test-cowork-model-log.XXXXXX)
rm -f "$LOG_FILE"
echo "$INPUT" | ANTHROPIC_MODEL='claude-sonnet-4-6' CC_COWORK_MODEL_LOG="$LOG_FILE" bash "$HOOK" >/dev/null 2>&1
if [ -f "$LOG_FILE" ] && grep -q "model=" "$LOG_FILE"; then
    echo "  PASS: writes log entry when CC_COWORK_MODEL_LOG set"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log file should contain entry"
    FAIL=$((FAIL + 1))
fi
rm -f "$LOG_FILE"

# --- Test 19: Log records is_1m flag ---
LOG_FILE=$(mktemp /tmp/test-cowork-model-log2.XXXXXX)
rm -f "$LOG_FILE"
echo "$INPUT" | ANTHROPIC_MODEL='claude-sonnet-4-6[1m]' CC_COWORK_MODEL_LOG="$LOG_FILE" bash "$HOOK" >/dev/null 2>&1
if grep -q "is_1m=1" "$LOG_FILE"; then
    echo "  PASS: log records is_1m=1 for 1m variant"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log should record is_1m=1"
    FAIL=$((FAIL + 1))
fi
rm -f "$LOG_FILE"

# --- Test 20: Suggests export form for shell init ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-sonnet-4-6[1m]')
if echo "$output" | grep -q "export ANTHROPIC_MODEL"; then
    echo "  PASS: suggests export ANTHROPIC_MODEL workaround"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should suggest export form"
    FAIL=$((FAIL + 1))
fi

# --- Test 21: Handles empty stdin ---
output=$(echo "" | ANTHROPIC_MODEL='claude-sonnet-4-6[1m]' bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: handles empty stdin"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should fire with empty stdin"
    FAIL=$((FAIL + 1))
fi

# --- Test 22: Handles no stdin at all ---
output=$(ANTHROPIC_MODEL='claude-sonnet-4-6[1m]' bash "$HOOK" </dev/null 2>&1 || true)
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: handles missing stdin"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should fire with no stdin"
    FAIL=$((FAIL + 1))
fi

# --- Test 23: Header documents the silent default ---
if grep -qi "silent" "$HOOK"; then
    echo "  PASS: header documents the silent default"
    PASS=$((PASS + 1))
else
    echo "  FAIL: header should document silent default"
    FAIL=$((FAIL + 1))
fi

# --- Test 24: Handles uppercase 1M ---
output=$(run_hook_with_env ANTHROPIC_MODEL='SONNET-1M')
if echo "$output" | grep -q "model exposure check"; then
    echo "  PASS: handles uppercase 1M suffix"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should handle uppercase 1M"
    FAIL=$((FAIL + 1))
fi

# --- Test 25: Safe model with 'haiku' is not flagged ---
output=$(run_hook_with_env ANTHROPIC_MODEL='claude-haiku-4-5')
if echo "$output" | grep -q "model exposure check"; then
    echo "  FAIL: haiku should not be flagged as 1m"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: haiku model not flagged as 1m"
    PASS=$((PASS + 1))
fi

# --- Summary ---
echo ""
echo "Tests: $((PASS + FAIL)) total, $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
