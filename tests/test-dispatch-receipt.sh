#!/bin/bash
# Tests for dispatch-receipt.sh
# Issue: anthropics/claude-code#61167 (nvst18 phantom-dispatch incident)
# Principle: subagent dispatch is an action that must produce a verifiable record

HOOK="examples/dispatch-receipt.sh"
PASS=0 FAIL=0

# Isolate receipts to a temp directory
TMPDIR_RECEIPTS=$(mktemp -d)
export CC_DISPATCH_RECEIPT_DIR="$TMPDIR_RECEIPTS"
cleanup() { [ -n "$TMPDIR_RECEIPTS" ] && [ -d "$TMPDIR_RECEIPTS" ] && find "$TMPDIR_RECEIPTS" -type f -delete && rmdir "$TMPDIR_RECEIPTS" 2>/dev/null; }
trap cleanup EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

reset_receipts() { find "$CC_DISPATCH_RECEIPT_DIR" -name '*.jsonl' -delete 2>/dev/null; }

# ----------------------------------------------------------------
# Group 1: Empty / malformed input silently passes
# ----------------------------------------------------------------

# Test 1: empty input silently passes
reset_receipts
unset CC_DISPATCH_ALLOWLIST
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
RECEIPT_COUNT=$(find "$CC_DISPATCH_RECEIPT_DIR" -name '*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_COUNT" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: empty input wrote receipt"; fi

# Test 2: tool_input with no fields silently passes
reset_receipts
OUT=$(echo '{"tool_input":{}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "tool_input empty exit 0" "$RC" "0"

# Test 3: completely invalid JSON treated as empty
reset_receipts
OUT=$(echo 'not json at all' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 2: Receipt-only mode (no allowlist)
# ----------------------------------------------------------------

# Test 4: dispatch with full payload, no allowlist, exits 0
reset_receipts
unset CC_DISPATCH_ALLOWLIST
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"survey","prompt":"survey state"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no-allowlist dispatch exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt has subagent_type" "$RECEIPT_BODY" '"subagent_type":"general-purpose"'
assert_contains "receipt has description" "$RECEIPT_BODY" '"description":"survey"'
assert_contains "receipt has decision execute" "$RECEIPT_BODY" '"decision":"execute"'
assert_contains "receipt has prompt_hash" "$RECEIPT_BODY" '"prompt_hash":"'
assert_contains "receipt has prompt_length" "$RECEIPT_BODY" '"prompt_length":12'

# Test 5: prompt is NOT stored verbatim in receipt (PHI safety)
reset_receipts
SENSITIVE_PROMPT="patient SSN 555-12-3456 needs review"
OUT=$(echo "{\"tool_input\":{\"subagent_type\":\"general-purpose\",\"description\":\"d\",\"prompt\":\"$SENSITIVE_PROMPT\"}}" | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_not_contains "receipt does not contain SSN" "$RECEIPT_BODY" "555-12-3456"
assert_not_contains "receipt does not contain 'patient'" "$RECEIPT_BODY" "patient SSN"

# Test 6: prompt_hash is deterministic and sha256
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"x","description":"d","prompt":"hello world"}}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
EXPECTED_HASH="b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
assert_contains "prompt_hash matches sha256('hello world')" "$RECEIPT_BODY" "$EXPECTED_HASH"

# Test 7: subagent_type defaults to general-purpose when missing
reset_receipts
OUT=$(echo '{"tool_input":{"description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing subagent_type exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "default subagent_type general-purpose" "$RECEIPT_BODY" '"subagent_type":"general-purpose"'

# ----------------------------------------------------------------
# Group 3: Allowlist mode — execute path
# ----------------------------------------------------------------

# Test 8: allowed agent passes through, receipt records match
reset_receipts
export CC_DISPATCH_ALLOWLIST='["general-purpose","Explore","code-reviewer"]'
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "allowed agent exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "allowlist_match recorded" "$RECEIPT_BODY" '"allowlist_match":"general-purpose"'
assert_contains "decision execute" "$RECEIPT_BODY" '"decision":"execute"'

# Test 9: Explore (another allowed) passes through
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"Explore","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Explore allowed exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "Explore allowlist match" "$RECEIPT_BODY" '"allowlist_match":"Explore"'

# ----------------------------------------------------------------
# Group 4: Allowlist mode — refuse path (nvst18 case)
# ----------------------------------------------------------------

# Test 10: CLINIC dispatch blocked when not in allowlist (nvst18 healthcare case)
reset_receipts
export CC_DISPATCH_ALLOWLIST='["general-purpose","Explore"]'
OUT=$(echo '{"tool_input":{"subagent_type":"CLINIC","description":"clinical review","prompt":"review compliance"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "CLINIC refused exit 2" "$RC" "2"
assert_contains "stderr names CLINIC" "$OUT" 'CLINIC'
assert_contains "stderr mentions BLOCKED" "$OUT" 'BLOCKED'
assert_contains "stderr names allowlist contents" "$OUT" 'general-purpose, Explore'
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "refused receipt records decision" "$RECEIPT_BODY" '"decision":"refuse"'
assert_contains "refused receipt records subagent_type" "$RECEIPT_BODY" '"subagent_type":"CLINIC"'
assert_contains "refused receipt allowlist_match null" "$RECEIPT_BODY" '"allowlist_match":null'

# Test 11: GUARD (another phantom from nvst18) also blocked
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"GUARD","description":"safety review","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "GUARD refused exit 2" "$RC" "2"

# Test 12: SABRINA (CEO daily briefs) — zero sessions in nvst18 audit — blocked
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"SABRINA","description":"daily brief","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "SABRINA refused exit 2" "$RC" "2"

# Test 13: stderr names the issue link for the refuse path
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"CLINIC","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
assert_contains "refuse stderr cites issue #61167" "$OUT" '61167'

# ----------------------------------------------------------------
# Group 5: Bypass mode
# ----------------------------------------------------------------

# Test 14: BYPASS=1 turns refuse into execute-bypassed
reset_receipts
export CC_DISPATCH_ALLOWLIST='["general-purpose"]'
export CC_DISPATCH_BYPASS=1
OUT=$(echo '{"tool_input":{"subagent_type":"CLINIC","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "BYPASS exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "BYPASS receipt decision" "$RECEIPT_BODY" '"decision":"execute-bypassed"'
unset CC_DISPATCH_BYPASS

# Test 15: BYPASS does not affect allowed dispatches (still execute, not execute-bypassed)
reset_receipts
export CC_DISPATCH_BYPASS=1
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "BYPASS on allowed stays execute" "$RECEIPT_BODY" '"decision":"execute"'
unset CC_DISPATCH_BYPASS

# ----------------------------------------------------------------
# Group 6: Allowlist edge cases
# ----------------------------------------------------------------

# Test 16: Empty array allowlist refuses everything (consistent with semantics)
reset_receipts
export CC_DISPATCH_ALLOWLIST='[]'
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty allowlist refuses" "$RC" "2"

# Test 17: Malformed allowlist (not array) fails open to receipt-only
reset_receipts
export CC_DISPATCH_ALLOWLIST='"not-an-array"'
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "malformed allowlist fails open" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "malformed allowlist still writes receipt" "$RECEIPT_BODY" '"decision":"execute"'

# Test 18: Allowlist as JSON object (invalid) fails open
reset_receipts
export CC_DISPATCH_ALLOWLIST='{"allowed":["general-purpose"]}'
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "JSON object allowlist fails open" "$RC" "0"

unset CC_DISPATCH_ALLOWLIST

# ----------------------------------------------------------------
# Group 7: Receipt format integrity
# ----------------------------------------------------------------

# Test 19: receipt is valid JSON (one line per dispatch)
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RECEIPT_LINE=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | head -1)
echo "$RECEIPT_LINE" | jq -e . >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt is not valid JSON: $RECEIPT_LINE"; fi

# Test 20: multiple dispatches append to same file
reset_receipts
echo '{"tool_input":{"subagent_type":"general-purpose","description":"a","prompt":"1"}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_input":{"subagent_type":"general-purpose","description":"b","prompt":"2"}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_input":{"subagent_type":"general-purpose","description":"c","prompt":"3"}}' | bash "$HOOK" >/dev/null 2>&1
LINE_COUNT=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | wc -l)
if [ "$LINE_COUNT" = "3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 3 receipt lines, got $LINE_COUNT"; fi

# Test 21: receipt timestamp is ISO 8601 UTC
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
TS=$(echo "$RECEIPT_BODY" | jq -r '.ts')
echo "$TS" | grep -qE '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: ts not ISO 8601 UTC: $TS"; fi

# Test 22: special characters in description do not break JSON
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"quote\"and\\backslash","prompt":"p"}}' | bash "$HOOK" 2>&1)
RECEIPT_LINE=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | head -1)
echo "$RECEIPT_LINE" | jq -e . >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: special chars broke JSON: $RECEIPT_LINE"; fi

# Test 23: newlines in description preserved as escapes in JSON
reset_receipts
PAYLOAD=$(jq -n --arg d "line1
line2" '{tool_input:{subagent_type:"general-purpose",description:$d,prompt:"p"}}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RECEIPT_LINE=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | head -1)
echo "$RECEIPT_LINE" | jq -e . >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: newlines broke JSON"; fi

# ----------------------------------------------------------------
# Group 8: Empty / large prompt handling
# ----------------------------------------------------------------

# Test 24: empty prompt still records receipt (subagent_type present)
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty prompt exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "empty prompt length 0" "$RECEIPT_BODY" '"prompt_length":0'

# Test 25: hash of empty string is the sha256 of empty
reset_receipts
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":""}}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "empty prompt hash" "$RECEIPT_BODY" 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'

# Test 26: large prompt (10 KB) handled cleanly
reset_receipts
LARGE=$(printf 'a%.0s' $(seq 1 10000))
PAYLOAD=$(jq -n --arg p "$LARGE" '{tool_input:{subagent_type:"general-purpose",description:"d",prompt:$p}}')
OUT=$(echo "$PAYLOAD" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "10KB prompt exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "10KB prompt length recorded" "$RECEIPT_BODY" '"prompt_length":10000'

# ----------------------------------------------------------------
# Group 9: Audit-query usability
# ----------------------------------------------------------------

# Test 27: nvst18 audit query "show me CLINIC dispatches" returns the truth
# (zero dispatches in the corpus = no fabrication can be recovered without grep)
reset_receipts
echo '{"tool_input":{"subagent_type":"general-purpose","description":"a","prompt":"1"}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_input":{"subagent_type":"general-purpose","description":"b","prompt":"2"}}' | bash "$HOOK" >/dev/null 2>&1
echo '{"tool_input":{"subagent_type":"Explore","description":"c","prompt":"3"}}' | bash "$HOOK" >/dev/null 2>&1
CLINIC_COUNT=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | jq -r 'select(.subagent_type == "CLINIC") | .ts' | wc -l)
if [ "$CLINIC_COUNT" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: CLINIC count expected 0, got $CLINIC_COUNT"; fi

# Test 28: audit "show me all dispatch types in corpus" returns distinct types
DISTINCT=$(cat "$CC_DISPATCH_RECEIPT_DIR"/*.jsonl 2>/dev/null | jq -r '.subagent_type' | sort -u | wc -l)
if [ "$DISTINCT" = "2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 2 distinct types (general-purpose, Explore), got $DISTINCT"; fi

# Test 29: receipt directory created if absent (smoke test against fresh tempdir)
FRESH=$(mktemp -d)
find "$FRESH" -mindepth 1 -delete 2>/dev/null
export CC_DISPATCH_RECEIPT_DIR="$FRESH/nested/dir"
OUT=$(echo '{"tool_input":{"subagent_type":"general-purpose","description":"d","prompt":"p"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "directory auto-created exit 0" "$RC" "0"
FRESH_COUNT=$(find "$FRESH/nested/dir" -name '*.jsonl' 2>/dev/null | wc -l)
if [ "$FRESH_COUNT" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: fresh dir receipt count $FRESH_COUNT"; fi
find "$FRESH" -type f -delete 2>/dev/null
find "$FRESH" -depth -type d -delete 2>/dev/null

# Restore main test directory
export CC_DISPATCH_RECEIPT_DIR="$TMPDIR_RECEIPTS"

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------

TOTAL=$((PASS+FAIL))
echo ""
echo "================================================"
echo "dispatch-receipt.sh tests"
echo "  Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "  Failed: $FAIL"
    exit 1
fi
echo "  All tests pass."
echo "================================================"
exit 0
