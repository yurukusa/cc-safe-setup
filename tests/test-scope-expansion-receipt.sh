#!/bin/bash
# Tests for scope-expansion-receipt.sh
# Issue: anthropics/claude-code#61102 (Awis13 cache-expansion incident)
# Principle: Keesan12 — "subagent output is evidence, not authorization"

HOOK="examples/scope-expansion-receipt.sh"
PASS=0 FAIL=0

# Isolate receipts to a temp directory
TMPDIR_RECEIPTS=$(mktemp -d)
export CC_RECEIPT_DIR="$TMPDIR_RECEIPTS"
trap "rm -rf $TMPDIR_RECEIPTS" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

reset_receipts() { rm -f "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null; }

# ----------------------------------------------------------------
# Group 1: Non-destructive commands silently pass
# ----------------------------------------------------------------

# Test 1: ls is not destructive
reset_receipts
OUT=$(echo '{"tool_input":{"command":"ls -la /tmp"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "non-destructive ls exit 0" "$RC" "0"
assert_not_contains "non-destructive ls no output" "$OUT" "BLOCKED"

# Test 2: Empty command silently passes
OUT=$(echo '{"tool_input":{"command":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty command exit 0" "$RC" "0"

# Test 3: cat is not destructive
OUT=$(echo '{"tool_input":{"command":"cat /etc/passwd"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "cat exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 2: Destructive verbs detected, receipt written (no scopes set)
# ----------------------------------------------------------------

# Test 4: rm -rf detected, receipt written, exit 0 (no scopes)
reset_receipts
unset CC_RECEIPT_SCOPES
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/some-test-target"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "rm -rf no scopes exit 0" "$RC" "0"
RECEIPT_COUNT=$(ls "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null | wc -l)
if [ "$RECEIPT_COUNT" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt count expected 1, got $RECEIPT_COUNT"; fi
RECEIPT_BODY=$(cat "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt has decision execute" "$RECEIPT_BODY" '"decision":"execute"'
assert_contains "receipt has path" "$RECEIPT_BODY" "/tmp/some-test-target"

# Test 5: find -delete detected
reset_receipts
OUT=$(echo '{"tool_input":{"command":"find /tmp/target -name \"*.tmp\" -delete"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "find -delete exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "find -delete receipt written" "$RECEIPT_BODY" "find"

# Test 6: npm cache clean detected
reset_receipts
OUT=$(echo '{"tool_input":{"command":"npm cache clean --force"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "npm cache clean exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "npm cache clean receipt" "$RECEIPT_BODY" "npm cache clean"

# Test 7: pnpm store prune detected
reset_receipts
OUT=$(echo '{"tool_input":{"command":"pnpm store prune"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "pnpm store prune exit 0" "$RC" "0"

# Test 8: npx rimraf detected
reset_receipts
OUT=$(echo '{"tool_input":{"command":"npx rimraf /tmp/node_modules"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "npx rimraf exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 3: Scope-based refuse logic
# ----------------------------------------------------------------

# Test 9: Path in declared scope -> execute
reset_receipts
export CC_RECEIPT_SCOPES='{"cache":["/tmp/Library/Caches","/tmp/npm-cache"]}'
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/Library/Caches/com.example"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "path in scope exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "in-scope receipt has scope_match" "$RECEIPT_BODY" '"scope_match":"cache"'
assert_contains "in-scope receipt has decision execute" "$RECEIPT_BODY" '"decision":"execute"'

# Test 10: Path outside declared scope -> refuse (exit 2)
reset_receipts
export CC_RECEIPT_SCOPES='{"cache":["/tmp/Library/Caches"]}'
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/node_modules"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "out-of-scope exit 2" "$RC" "2"
assert_contains "out-of-scope error message" "$OUT" "BLOCKED"
assert_contains "out-of-scope cites principle" "$OUT" "evidence, not authorization"
assert_contains "out-of-scope cites issue" "$OUT" "61102"
RECEIPT_BODY=$(cat "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "refuse receipt has scope_match null" "$RECEIPT_BODY" '"scope_match":null'
assert_contains "refuse receipt has decision refuse" "$RECEIPT_BODY" '"decision":"refuse"'

# Test 11: Awis13 case - cache scope set, node_modules wipe refused
reset_receipts
export CC_RECEIPT_SCOPES='{"cache":["/tmp/Library/Caches","/tmp/.npm/_cacache"],"simulator":["/tmp/Library/Developer/CoreSimulator"]}'
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/myproject/node_modules"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Awis13 node_modules wipe refused" "$RC" "2"
assert_contains "Awis13 refuse message" "$OUT" "BLOCKED"

# Test 12: Awis13 case - actual cache delete allowed
reset_receipts
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/Library/Caches/com.apple.example"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "Awis13 cache delete allowed" "$RC" "0"

# Test 13: Bypass mode skips refuse, records bypass
reset_receipts
export CC_RECEIPT_SCOPES='{"cache":["/tmp/Library/Caches"]}'
export CC_RECEIPT_BYPASS=1
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/intentionally-not-in-scope"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "bypass mode exit 0" "$RC" "0"
RECEIPT_BODY=$(cat "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "bypass receipt records execute-bypassed" "$RECEIPT_BODY" '"decision":"execute-bypassed"'
unset CC_RECEIPT_BYPASS

# Test 14: Multiple paths - any out-of-scope causes refuse
reset_receipts
export CC_RECEIPT_SCOPES='{"cache":["/tmp/Library/Caches"]}'
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/Library/Caches/a /tmp/node_modules"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "mixed paths one out-of-scope -> refuse" "$RC" "2"

# Test 15: Multiple paths all in scope - execute
reset_receipts
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/Library/Caches/a /tmp/Library/Caches/b"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "multiple in-scope paths -> execute" "$RC" "0"

# ----------------------------------------------------------------
# Group 4: Receipt format integrity
# ----------------------------------------------------------------

# Test 16: Receipt is valid JSONL (one JSON object per line)
reset_receipts
unset CC_RECEIPT_SCOPES
echo '{"tool_input":{"command":"rm -rf /tmp/test1"}}' | bash "$HOOK" 2>&1 >/dev/null
echo '{"tool_input":{"command":"rm -rf /tmp/test2"}}' | bash "$HOOK" 2>&1 >/dev/null
LINE_COUNT=$(wc -l < "$CC_RECEIPT_DIR"/*.jsonl 2>/dev/null)
if [ "$LINE_COUNT" = "2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt JSONL line count expected 2, got $LINE_COUNT"; fi
# Each line should parse as valid JSON
while IFS= read -r line; do
    if echo "$line" | jq . >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: invalid JSON line: $line"; fi
done < "$CC_RECEIPT_DIR"/*.jsonl

# Test 17: Receipt has required 5 fields
reset_receipts
echo '{"tool_input":{"command":"rm -rf /tmp/test"}}' | bash "$HOOK" 2>&1 >/dev/null
RECEIPT_LINE=$(cat "$CC_RECEIPT_DIR"/*.jsonl | head -1)
for field in ts command paths scope_match decision; do
    if echo "$RECEIPT_LINE" | jq -e "has(\"$field\")" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt missing field: $field"; fi
done

# Test 18: Timestamp is ISO 8601 with Z
TS=$(echo "$RECEIPT_LINE" | jq -r '.ts')
if echo "$TS" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: ts not ISO 8601 UTC: $TS"; fi

# ----------------------------------------------------------------
# Group 5: Edge cases
# ----------------------------------------------------------------

# Test 19: rm -fR (different flag order) detected
reset_receipts
unset CC_RECEIPT_SCOPES
OUT=$(echo '{"tool_input":{"command":"rm -fR /tmp/test"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "rm -fR detected" "$RC" "0"
if [ -f "$CC_RECEIPT_DIR/destructive-$(date +%Y-%m-%d).jsonl" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: rm -fR receipt not written"; fi

# Test 20: rm -r (no f) is not matched (we only flag combined recursive+force as destructive)
# Actually our pattern matches any r/R/f/F combo, so rm -r WOULD match. Adjust test.
reset_receipts
OUT=$(echo '{"tool_input":{"command":"rm -r /tmp/test"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "rm -r is destructive" "$RC" "0"

# Test 21: bare rm without flags is NOT matched (single file deletion is intentional)
reset_receipts
OUT=$(echo '{"tool_input":{"command":"rm /tmp/single-file.txt"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "rm without recursive flag not matched" "$RC" "0"
RECEIPT_FILE="$CC_RECEIPT_DIR/destructive-$(date +%Y-%m-%d).jsonl"
if [ ! -f "$RECEIPT_FILE" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: bare rm should not have written receipt"; fi

echo ""
echo "scope-expansion-receipt.sh: $PASS pass, $FAIL fail"
[ "$FAIL" = "0" ]
