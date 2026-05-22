#!/bin/bash
# Tests for userprompt-submit-receipt.sh
# Architecture: https://github.com/anthropics/claude-code/issues/61102#issuecomment-4514215413
# Purpose: companion log for articulated_scope at the prompt boundary,
#          joined by downstream receipt hooks (dispatch / bash / edit)

HOOK="examples/userprompt-submit-receipt.sh"
PASS=0 FAIL=0

TMPDIR_RECEIPTS=$(mktemp -d)
export CC_DISPATCH_RECEIPT_DIR="$TMPDIR_RECEIPTS"

cleanup() {
    [ -n "$TMPDIR_RECEIPTS" ] && [ -d "$TMPDIR_RECEIPTS" ] && find "$TMPDIR_RECEIPTS" -type f -delete && rmdir "$TMPDIR_RECEIPTS" 2>/dev/null
}
trap cleanup EXIT

assert_contains() { if echo "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

reset_state() {
    find "$CC_DISPATCH_RECEIPT_DIR" -name '*.jsonl' -delete 2>/dev/null
    unset CC_USERPROMPT_RECEIPT_OFF
}

# ----------------------------------------------------------------
# Group 1: Basic operation
# ----------------------------------------------------------------

# Test 1: prompt at .user_message is captured
reset_state
OUT=$(echo '{"user_message":"hello world"}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "user_message exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
EXPECTED_HASH="b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
assert_contains "prompt_hash matches sha256(hello world)" "$RECEIPT_BODY" "$EXPECTED_HASH"
assert_contains "prompt_length captured" "$RECEIPT_BODY" '"prompt_length":11'
assert_contains "schema_version 1" "$RECEIPT_BODY" '"schema_version":1'

# Test 2: prompt at .prompt is captured (alternative field name)
reset_state
OUT=$(echo '{"prompt":"hello world"}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit ".prompt exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains ".prompt hash captured" "$RECEIPT_BODY" "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

# Test 3: no prompt → silent pass, no receipt
reset_state
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
RECEIPT_FILES=$(find "$CC_DISPATCH_RECEIPT_DIR" -name 'userprompt-submit-*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_FILES" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: empty input wrote receipt"; fi

# Test 4: invalid JSON → silent pass
reset_state
OUT=$(echo 'not json' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 2: PHI safety — prompt is never persisted verbatim
# ----------------------------------------------------------------

# Test 5: sensitive content in prompt is not stored verbatim
reset_state
SENSITIVE='patient SSN 123-45-6789 needs review'
echo "{\"user_message\":\"$SENSITIVE\"}" | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_not_contains "receipt does not contain SSN" "$RECEIPT_BODY" "123-45-6789"
assert_not_contains "receipt does not contain 'patient'" "$RECEIPT_BODY" "patient SSN"
assert_contains "receipt has prompt_hash field" "$RECEIPT_BODY" '"prompt_hash"'

# ----------------------------------------------------------------
# Group 3: Receipt format integrity
# ----------------------------------------------------------------

# Test 6: receipt is valid JSONL
reset_state
echo '{"user_message":"first"}' | bash "$HOOK" >/dev/null 2>&1
echo '{"user_message":"second"}' | bash "$HOOK" >/dev/null 2>&1
LINES_OK=0
LINES_TOTAL=0
while IFS= read -r line; do
    LINES_TOTAL=$((LINES_TOTAL+1))
    if echo "$line" | jq . >/dev/null 2>&1; then
        LINES_OK=$((LINES_OK+1))
    fi
done < "$CC_DISPATCH_RECEIPT_DIR"/userprompt-submit-*.jsonl
if [ "$LINES_OK" = "2" ] && [ "$LINES_TOTAL" = "2" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: receipt JSONL not valid (got $LINES_OK/$LINES_TOTAL valid)"
fi

# Test 7: ISO 8601 UTC timestamp
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | head -1)
assert_contains "ts ISO 8601 UTC" "$RECEIPT_BODY" '"ts":"20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z"'

# Test 8: prompt_hash is sha256 length (64 hex chars)
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | head -1)
assert_contains "prompt_hash is 64-char sha256" "$RECEIPT_BODY" '"prompt_hash":"[a-f0-9]\{64\}"'

# ----------------------------------------------------------------
# Group 4: Configuration — CC_USERPROMPT_RECEIPT_OFF
# ----------------------------------------------------------------

# Test 9: CC_USERPROMPT_RECEIPT_OFF=1 → no receipt written
reset_state
export CC_USERPROMPT_RECEIPT_OFF=1
echo '{"user_message":"hello"}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_FILES=$(find "$CC_DISPATCH_RECEIPT_DIR" -name 'userprompt-submit-*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_FILES" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: OFF=1 wrote receipt"; fi
unset CC_USERPROMPT_RECEIPT_OFF

# Test 10: CC_USERPROMPT_RECEIPT_OFF=0 → receipt is written (off by default off)
reset_state
export CC_USERPROMPT_RECEIPT_OFF=0
echo '{"user_message":"hello"}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_FILES=$(find "$CC_DISPATCH_RECEIPT_DIR" -name 'userprompt-submit-*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_FILES" -ge "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: OFF=0 did not write receipt"; fi
unset CC_USERPROMPT_RECEIPT_OFF

# ----------------------------------------------------------------
# Group 5: Edge cases
# ----------------------------------------------------------------

# Test 11: very large prompt (10KB) handled
reset_state
BIG=$(python3 -c "print('x' * 10000)")
PAYLOAD=$(printf '{"user_message":%s}' "$(printf '%s' "$BIG" | jq -Rs .)")
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "10KB prompt exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "10KB prompt length recorded" "$RECEIPT_BODY" '"prompt_length":100[0-9][0-9]'

# Test 12: prompt with newlines
reset_state
echo '{"user_message":"line1\nline2\nline3"}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
# Hash is deterministic — verify it exists
assert_contains "newline prompt hash exists" "$RECEIPT_BODY" '"prompt_hash":"[a-f0-9]\{64\}"'

# Test 13: prompt with quotes
reset_state
echo '{"user_message":"say \"hello\""}' | bash "$HOOK" >/dev/null 2>&1
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "quoted prompt hash exists" "$RECEIPT_BODY" '"prompt_hash":"[a-f0-9]\{64\}"'

# ----------------------------------------------------------------
# Group 6: Integration with downstream consumer
# ----------------------------------------------------------------

# Test 14: companion log is read by dispatch-allowlist-preflight downstream
reset_state
echo '{"user_message":"my articulated scope"}' | bash "$HOOK" >/dev/null 2>&1
COMPANION_RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/userprompt-submit-*.jsonl 2>/dev/null)
COMPANION_HASH=$(echo "$COMPANION_RECEIPT_BODY" | jq -r '.prompt_hash')

DOWNSTREAM_HOOK="examples/dispatch-allowlist-preflight.sh"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"x","prompt":"dispatch p"}}' | bash "$DOWNSTREAM_HOOK" >/dev/null 2>&1
DOWNSTREAM_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/dispatch-preflight-*.jsonl 2>/dev/null | tail -1)
DOWNSTREAM_ART_HASH=$(echo "$DOWNSTREAM_BODY" | jq -r '.articulated_scope_hash')
if [ "$DOWNSTREAM_ART_HASH" = "$COMPANION_HASH" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL: downstream did not inherit companion hash (got $DOWNSTREAM_ART_HASH, expected $COMPANION_HASH)"
fi

echo ""
echo "===================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "===================="
[ "$FAIL" = "0" ] && exit 0 || exit 1
