#!/bin/bash
# Tests for articulated-scope-capture.sh
#
# Verifies the UserPromptSubmit-time prompt-hash + length capture:
#   - Valid .prompt → writes JSONL receipt with hash + length + boundary_type
#   - Empty input / missing .prompt → exit 0, no receipt written
#   - CC_ARTICULATED_SCOPE_DISABLE=1 → disables capture entirely
#   - PHI / secret safety → raw prompt text MUST NOT appear in receipt
#   - Multiple prompts in same session → multiple JSONL lines, append-only

set -uo pipefail

HOOK="$(dirname "$0")/../examples/articulated-scope-capture.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Isolated receipt directory per test run
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
export CC_RECEIPT_DIR="$TMPDIR/receipts"

DATE=$(date -u +"%Y-%m-%d")
RECEIPT_FILE="$CC_RECEIPT_DIR/articulated-scope-${DATE}.jsonl"

echo "=== articulated-scope-capture.sh tests ==="

# --- Test 1: valid prompt → JSONL line written with all schema fields ---
INPUT=$(jq -nc '{
    prompt: "delete caches and simulators",
    session_id: "test-session-1",
    hook_event_name: "UserPromptSubmit"
}')
rc=0
printf '%s' "$INPUT" | bash "$HOOK" || rc=$?
if [ "$rc" -eq 0 ] && [ -f "$RECEIPT_FILE" ]; then
    assert_pass "valid prompt → exit 0 + receipt file created"
else
    assert_fail "expected exit 0 + receipt file, got rc=$rc file_exists=$([ -f "$RECEIPT_FILE" ] && echo yes || echo no)"
fi

# --- Test 2: receipt JSONL contains required schema fields ---
LINE=$(tail -1 "$RECEIPT_FILE")
if echo "$LINE" | jq -e '.articulated_scope_hash and .articulated_scope_length and .boundary_type == "user_prompt_submit" and .ts and .session_id == "test-session-1"' > /dev/null 2>&1; then
    assert_pass "receipt schema fields present and well-typed"
else
    assert_fail "receipt schema check failed for line: $LINE"
fi

# --- Test 3: length correct for known input ---
# "delete caches and simulators" = 28 bytes (let LEN compute it independently)
EXPECTED_LEN=$(printf '%s' "delete caches and simulators" | wc -c | tr -d ' ')
ACTUAL_LEN=$(echo "$LINE" | jq -r '.articulated_scope_length')
if [ "$EXPECTED_LEN" = "$ACTUAL_LEN" ]; then
    assert_pass "articulated_scope_length = $ACTUAL_LEN (matches wc -c)"
else
    assert_fail "articulated_scope_length expected $EXPECTED_LEN, got $ACTUAL_LEN"
fi

# --- Test 4: sha256 hash is 64 hex chars ---
HASH=$(echo "$LINE" | jq -r '.articulated_scope_hash')
if [ "${#HASH}" -eq 64 ] && echo "$HASH" | grep -qE '^[0-9a-f]{64}$'; then
    assert_pass "articulated_scope_hash is 64 hex chars"
else
    assert_fail "articulated_scope_hash format wrong: $HASH"
fi

# --- Test 5: empty stdin → exit 0, no new line written ---
LINES_BEFORE=$(wc -l < "$RECEIPT_FILE")
rc=0
printf '' | bash "$HOOK" || rc=$?
LINES_AFTER=$(wc -l < "$RECEIPT_FILE")
if [ "$rc" -eq 0 ] && [ "$LINES_BEFORE" -eq "$LINES_AFTER" ]; then
    assert_pass "empty stdin → exit 0 + no receipt appended"
else
    assert_fail "empty stdin handling wrong: rc=$rc before=$LINES_BEFORE after=$LINES_AFTER"
fi

# --- Test 6: missing .prompt field → exit 0, no new line ---
INPUT=$(jq -nc '{session_id: "no-prompt-test"}')
LINES_BEFORE=$(wc -l < "$RECEIPT_FILE")
rc=0
printf '%s' "$INPUT" | bash "$HOOK" || rc=$?
LINES_AFTER=$(wc -l < "$RECEIPT_FILE")
if [ "$rc" -eq 0 ] && [ "$LINES_BEFORE" -eq "$LINES_AFTER" ]; then
    assert_pass "missing .prompt → exit 0 + no receipt appended"
else
    assert_fail "missing .prompt handling wrong: rc=$rc before=$LINES_BEFORE after=$LINES_AFTER"
fi

# --- Test 7: CC_ARTICULATED_SCOPE_DISABLE=1 → disabled, no write ---
INPUT=$(jq -nc '{prompt: "this should not be recorded", session_id: "disabled-test"}')
LINES_BEFORE=$(wc -l < "$RECEIPT_FILE")
rc=0
printf '%s' "$INPUT" | CC_ARTICULATED_SCOPE_DISABLE=1 bash "$HOOK" || rc=$?
LINES_AFTER=$(wc -l < "$RECEIPT_FILE")
if [ "$rc" -eq 0 ] && [ "$LINES_BEFORE" -eq "$LINES_AFTER" ]; then
    assert_pass "CC_ARTICULATED_SCOPE_DISABLE=1 → disabled + no receipt"
else
    assert_fail "disable flag not honored: rc=$rc before=$LINES_BEFORE after=$LINES_AFTER"
fi

# --- Test 8: PHI safety — raw prompt MUST NOT appear in receipt ---
INPUT=$(jq -nc '{
    prompt: "PATIENT_NAME=Jane Doe MRN=123456 review labs",
    session_id: "phi-safety-test"
}')
printf '%s' "$INPUT" | bash "$HOOK"
LINE=$(tail -1 "$RECEIPT_FILE")
if echo "$LINE" | grep -q "Jane Doe"; then
    assert_fail "PHI LEAK: raw name 'Jane Doe' found in receipt"
elif echo "$LINE" | grep -q "MRN=123456"; then
    assert_fail "PHI LEAK: raw MRN '123456' found in receipt"
elif echo "$LINE" | grep -q "PATIENT_NAME"; then
    assert_fail "PHI LEAK: 'PATIENT_NAME' label found in receipt"
else
    assert_pass "PHI-safe: raw prompt text not present in receipt (hash + length only)"
fi

# --- Test 9: multiple prompts in same session → multiple JSONL lines ---
INPUT_A=$(jq -nc '{prompt: "first prompt", session_id: "multi-test"}')
INPUT_B=$(jq -nc '{prompt: "second prompt", session_id: "multi-test"}')
LINES_BEFORE=$(wc -l < "$RECEIPT_FILE")
printf '%s' "$INPUT_A" | bash "$HOOK"
printf '%s' "$INPUT_B" | bash "$HOOK"
LINES_AFTER=$(wc -l < "$RECEIPT_FILE")
EXPECTED=$((LINES_BEFORE + 2))
if [ "$LINES_AFTER" -eq "$EXPECTED" ]; then
    assert_pass "multiple prompts → multiple JSONL lines (append-only)"
else
    assert_fail "append-only check failed: before=$LINES_BEFORE expected=$EXPECTED after=$LINES_AFTER"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
