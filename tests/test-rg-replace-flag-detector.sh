#!/bin/bash
# Tests for rg-replace-flag-detector.sh
#
# Verifies the PreToolUse-Bash hook behavior from anthropics/claude-code#62016:
#   - `rg -rn pattern path` → advisory fires (exit 0 + stderr)
#   - `rg -r TEXT pattern` (intentional replace) → advisory fires (false-positive accepted)
#   - `rg -n pattern path` → silent pass (no false-positive on correct usage)
#   - `rg "pattern" path` → silent pass
#   - `grep -rn pattern path` → silent pass (not rg)
#   - Strict mode → exit 2 instead of exit 0
#   - Disable flag → silent pass

set -uo pipefail

HOOK="$(dirname "$0")/../examples/rg-replace-flag-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_hook() {
    local cmd="$1"
    local extra_env="${2:-}"
    local input
    input=$(jq -nc --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}')
    if [ -n "$extra_env" ]; then
        eval "$extra_env bash \"$HOOK\"" <<< "$input" 2>&1
    else
        printf '%s' "$input" | bash "$HOOK" 2>&1
    fi
}

echo "=== rg-replace-flag-detector.sh tests ==="

# --- Test 1: rg -rn pattern → advisory fires ---
output=$(run_hook 'rg -rn "function generateTimeslotsForBranch" app/')
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "rg -rn fires advisory"
else
    assert_fail "expected exit 0 + advisory for rg -rn, got rc=$rc output=$output"
fi

# --- Test 2: rg -rln pattern → advisory fires ---
output=$(run_hook 'rg -rln "preventStrayRequests" tests/')
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "rg -rln fires advisory"
else
    assert_fail "expected exit 0 + advisory for rg -rln, got rc=$rc output=$output"
fi

# --- Test 3: rg --replace=X explicit → advisory fires ---
output=$(run_hook 'rg --replace=X "pattern" file.txt')
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "rg --replace= fires advisory"
else
    assert_fail "expected exit 0 + advisory for rg --replace=, got rc=$rc output=$output"
fi

# --- Test 4: rg -n pattern → silent pass (correct usage) ---
output=$(run_hook 'rg -n "function foo" src/')
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "rg -n silent pass"
else
    assert_fail "expected silent exit 0 for rg -n, got rc=$rc output=$output"
fi

# --- Test 5: rg "pattern" path → silent pass ---
output=$(run_hook 'rg "TODO" .')
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "bare rg silent pass"
else
    assert_fail "expected silent exit 0 for bare rg, got rc=$rc output=$output"
fi

# --- Test 6: grep -rn → silent pass (not rg) ---
output=$(run_hook 'grep -rn "pattern" .')
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "grep -rn silent (not rg)"
else
    assert_fail "expected silent exit 0 for grep -rn, got rc=$rc output=$output"
fi

# --- Test 7: rg -i pattern → silent pass (case-insensitive, no -r) ---
output=$(run_hook 'rg -i "pattern" src/')
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "rg -i silent pass"
else
    assert_fail "expected silent exit 0 for rg -i, got rc=$rc output=$output"
fi

# --- Test 8: rg -e pattern → silent pass (extended regex, no -r) ---
output=$(run_hook 'rg -e "pattern" .')
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "rg -e silent pass"
else
    assert_fail "expected silent exit 0 for rg -e, got rc=$rc output=$output"
fi

# --- Test 9: strict mode → exit 2 ---
output=$(run_hook 'rg -rn "pattern" .' 'CC_RG_REPLACE_DETECTOR_MODE=strict')
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "strict mode exits 2"
else
    assert_fail "expected exit 2 in strict mode, got rc=$rc output=$output"
fi

# --- Test 10: disable flag → silent ---
output=$(run_hook 'rg -rn "pattern" .' 'CC_RG_REPLACE_DETECTOR_DISABLE=1')
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag silent pass"
else
    assert_fail "expected silent exit 0 when disabled, got rc=$rc output=$output"
fi

# --- Test 11: non-Bash tool → silent pass ---
INPUT=$(jq -nc '{tool_name: "Edit", tool_input: {file_path: "/x", new_string: "rg -rn"}}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-Bash tool silent"
else
    assert_fail "expected silent exit 0 for non-Bash, got rc=$rc output=$output"
fi

# --- Test 12: empty stdin → silent pass ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty stdin silent"
else
    assert_fail "expected silent exit 0 for empty stdin, got rc=$rc output=$output"
fi

# --- Test 13: rg -r (just -r, no other flags) → advisory ---
output=$(run_hook 'rg -r REPLACEMENT "pattern" file.txt')
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "rg -r alone fires advisory"
else
    assert_fail "expected exit 0 + advisory for rg -r, got rc=$rc output=$output"
fi

# --- Test 14: rg with pipe → still detected ---
output=$(run_hook 'find . -type f | xargs rg -rn pattern')
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "rg -rn after pipe still detected"
else
    assert_fail "expected exit 0 + advisory for piped rg -rn, got rc=$rc output=$output"
fi

# --- Test 15: rg -e then -r → still detected (mixed) ---
output=$(run_hook 'rg -e "regex" -r REPLACEMENT file')
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "rg-replace-flag-detector"; then
    assert_pass "rg with -e and -r mixed still detected"
else
    assert_fail "expected exit 0 + advisory for rg -e -r, got rc=$rc output=$output"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
