#!/bin/bash
# Tests for refusal-arrest-gate.sh
#
# Verifies the PreToolUse-hook behavior for the refusal-side dual of
# closure-word-verify-gate (#60506, #60475):
#   - Refusal in same-turn prose + matching tool target  → exit 2, feedback
#   - Refusal in same-turn prose + non-matching target   → exit 0 silent
#   - No refusal in prose                                → exit 0 silent
#   - Refusal inside quoted user prompt                  → exit 0 silent
#   - Disable flag respected
#   - Multiple refusal pattern variants
#   - Bash command target matching
#   - File path basename matching
#   - Length threshold (very short targets ignored)
#   - Non-instrumented tools pass through

set -uo pipefail

HOOK="$(dirname "$0")/../examples/refusal-arrest-gate.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Helper: build PreToolUse input JSON from three params, then run hook.
# Args: tool_name, tool_input_json, assistant_text
make_input() {
    local tn="$1" ti="$2" at="$3"
    jq -nc \
        --arg tn "$tn" \
        --argjson ti "$ti" \
        --arg at "$at" \
        '{tool_name: $tn, tool_input: $ti, last_assistant_message: $at}'
}

run_hook() {
    local input="$1"
    local extra_env="${2:-}"
    if [ -n "$extra_env" ]; then
        env $extra_env bash "$HOOK" <<< "$input" 2>&1
    else
        printf '%s' "$input" | bash "$HOOK" 2>&1
    fi
}

echo "=== refusal-arrest-gate.sh tests ==="

# --- Test 1: refusal + matching Edit target → blocks ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "I will not modify config.json — the operator already finalized it.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "REFUSAL-SIDE ARREST"; then
    assert_pass "refusal + matching Edit target → exit 2 with feedback"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc output=$output"
fi

# --- Test 2: refusal + non-matching Edit target → silent pass ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/other.json"}' \
    "I will not modify config.json — the operator already finalized it.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "refusal + non-matching target → silent pass"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 3: no refusal → silent pass ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "Updating config.json with the new endpoint.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no refusal in prose → silent pass"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 4: "I won't" variant + matching target → blocks ---
INPUT=$(make_input "Write" '{"file_path":"/repo/migrations/0042.sql"}' \
    "I won't modify migrations until the lock is released.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "I won't variant triggers refusal arrest"
else
    assert_fail "expected exit 2, got rc=$rc output=$output"
fi

# --- Test 5: "I'll skip" variant + matching target → blocks ---
INPUT=$(make_input "Bash" '{"command":"pytest tests/integration/"}' \
    "I'll skip integration since unit tests cover this path.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "I'll skip variant triggers on Bash command"
else
    assert_fail "expected exit 2, got rc=$rc output=$output"
fi

# --- Test 6: "I'll preserve" variant + matching target → blocks ---
INPUT=$(make_input "Write" '{"file_path":"/repo/data/customers.csv"}' \
    "I'll preserve customers.csv as-is and write to a new file.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "I'll preserve variant triggers when contradicted"
else
    assert_fail "expected exit 2, got rc=$rc output=$output"
fi

# --- Test 7: "let me not" variant ---
INPUT=$(make_input "Edit" '{"file_path":"/etc/hosts"}' \
    "Let me not touch hosts file — the operator owns DNS.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "let me not variant triggers"
else
    assert_fail "expected exit 2, got rc=$rc output=$output"
fi

# --- Test 8: refusal inside <user_prompt> tag → silent pass ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "The user wrote: <user_prompt>I will not modify config.json</user_prompt> — I am now updating per the new request.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "refusal inside user_prompt tag → silent pass"
else
    assert_fail "expected silent exit 0 (user-quote ignored), got rc=$rc output=$output"
fi

# --- Test 9: refusal in markdown blockquote → silent pass ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "User said:
> I will not modify config.json without review
Proceeding with the requested change.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "refusal in markdown blockquote → silent pass"
else
    assert_fail "expected silent exit 0 (blockquote ignored), got rc=$rc output=$output"
fi

# --- Test 10: disable flag respected ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "I will not modify config.json.")
output=$(CC_REFUSAL_GATE_DISABLE=1 bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_REFUSAL_GATE_DISABLE=1 silences the gate"
else
    assert_fail "expected silent disable, got rc=$rc output=$output"
fi

# --- Test 11: empty input → silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input → silent no-op"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 12: missing tool_name → silent ---
INPUT=$(jq -nc '{tool_input: {file_path: "/repo/src/config.json"}, last_assistant_message: "I will not modify config.json."}')
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing tool_name → silent pass"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 13: unknown tool type (WebFetch) → silent ---
INPUT=$(make_input "WebFetch" '{"url":"https://example.com"}' \
    "I will not fetch example.com.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-instrumented tool (WebFetch) → silent pass"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 14: refusal with basename match (no path in refusal) → blocks ---
INPUT=$(make_input "Edit" '{"file_path":"/very/deep/nested/path/secrets.env"}' \
    "I will not modify secrets.env — credentials are operator-managed.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "basename match on deep path → blocks"
else
    assert_fail "expected exit 2 (basename match), got rc=$rc output=$output"
fi

# --- Test 15: short target word filter (≤2 chars) → no match ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/x.txt"}' \
    "I will not modify x — it is a test fixture.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "short target (≤2 chars) does not trigger (false-positive guard)"
else
    assert_fail "expected silent exit 0 (length threshold), got rc=$rc output=$output"
fi

# --- Test 16: refusal target appears in Bash command → blocks ---
INPUT=$(make_input "Bash" '{"command":"rm -rf node_modules/"}' \
    "I will not delete node_modules — the operator just ran npm install.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "Bash command containing refusal target → blocks"
else
    assert_fail "expected exit 2 (Bash target match), got rc=$rc output=$output"
fi

# --- Test 17: Bash command not matching refusal target → silent pass ---
INPUT=$(make_input "Bash" '{"command":"ls -la"}' \
    "I will not delete node_modules.")
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "Bash command not matching refusal target → silent pass"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 18: missing assistant text → silent pass ---
INPUT=$(jq -nc '{tool_name: "Edit", tool_input: {file_path: "/repo/src/config.json"}}')
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing assistant text → silent pass (no false positive)"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 19: custom CC_REFUSAL_PATTERNS does not crash ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "yapmayacağım config.json üzerinde değişiklik.")
output=$(CC_REFUSAL_PATTERNS='yapmayacağım [a-zA-Z0-9_./@\-]+' bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
    assert_pass "custom CC_REFUSAL_PATTERNS does not crash hook"
else
    assert_fail "custom pattern caused crash rc=$rc output=$output"
fi

# --- Test 20: feedback message cites #60506 / #60475 ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "I will not modify config.json under any circumstance.")
output=$(run_hook "$INPUT")
if echo "$output" | grep -q "60506" && echo "$output" | grep -q "60475"; then
    assert_pass "feedback message cites both #60506 and #60475"
else
    assert_fail "expected references to #60506 and #60475 in feedback"
fi

# --- Test 21: feedback message names the disable escape ---
INPUT=$(make_input "Edit" '{"file_path":"/repo/src/config.json"}' \
    "I will not modify config.json.")
output=$(run_hook "$INPUT")
if echo "$output" | grep -q "CC_REFUSAL_GATE_DISABLE=1"; then
    assert_pass "feedback message names the disable escape"
else
    assert_fail "expected CC_REFUSAL_GATE_DISABLE=1 mention in feedback"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
