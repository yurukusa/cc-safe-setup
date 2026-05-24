#!/bin/bash
# Tests for deployment-readback-gate.sh
# Issue: anthropics/claude-code#61699 (deployment-claim verification gap)
# Tracking: https://github.com/yurukusa/cc-safe-setup/issues/313
# Principle: deployment-completion claims must reconcile with the deployment
#            system's authoritative state via an out-of-band-source check.

HOOK="examples/deployment-readback-gate.sh"
PASS=0 FAIL=0

# Isolate receipts and mock adapter binaries
TMPDIR_RECEIPTS=$(mktemp -d)
TMPDIR_MOCKS=$(mktemp -d)
export DRG_RECEIPT_DIR="$TMPDIR_RECEIPTS"

cleanup() {
    [ -n "$TMPDIR_RECEIPTS" ] && [ -d "$TMPDIR_RECEIPTS" ] && find "$TMPDIR_RECEIPTS" -type f -delete && rmdir "$TMPDIR_RECEIPTS" 2>/dev/null
    [ -n "$TMPDIR_MOCKS" ] && [ -d "$TMPDIR_MOCKS" ] && find "$TMPDIR_MOCKS" -type f -delete && rmdir "$TMPDIR_MOCKS" 2>/dev/null
}
trap cleanup EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

reset_receipts() { find "$DRG_RECEIPT_DIR" -name '*.jsonl' -delete 2>/dev/null; }
reset_env() {
    unset DRG_ADAPTER DRG_PHRASE_LIST DRG_GH_REPO DRG_KUBECTL_NAMESPACE \
        DRG_KUBECTL_DEPLOYMENT DRG_TERRAFORM_OUTPUT DRG_STRICT_MODE DRG_BYPASS
}

make_mock() {
    # $1 = name, $2 = exit code, $3 = stdout
    local name="$1"
    local code="$2"
    local out="$3"
    cat > "$TMPDIR_MOCKS/$name" <<EOF
#!/bin/bash
printf '%s' '$out'
exit $code
EOF
    chmod +x "$TMPDIR_MOCKS/$name"
}

# ----------------------------------------------------------------
# Group 1: Empty / silent-pass cases (5 tests)
# ----------------------------------------------------------------

# Test 1: empty input silently passes
reset_env; reset_receipts
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
RECEIPT_COUNT=$(find "$DRG_RECEIPT_DIR" -name '*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_COUNT" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: empty input wrote receipt"; fi

# Test 2: invalid JSON treated as empty
reset_env; reset_receipts
OUT=$(echo 'not json' | bash "$HOOK" 2>&1)
assert_exit "invalid JSON exit 0" "$?" "0"

# Test 3: closeout_text with no deployment phrase silently passes
reset_env; reset_receipts
OUT=$(echo '{"closeout_text":"I refactored the function and added tests."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no phrase match exit 0" "$RC" "0"
RECEIPT_COUNT=$(find "$DRG_RECEIPT_DIR" -name '*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_COUNT" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: no-phrase wrote receipt"; fi

# Test 4: phrase present but no adapter configured silently passes
reset_env; reset_receipts
OUT=$(echo '{"closeout_text":"Successfully deployed the change."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "phrase but no adapter exit 0" "$RC" "0"

# Test 5: phrase present, unknown adapter silently passes
reset_env; reset_receipts
export DRG_ADAPTER="unknown-adapter"
OUT=$(echo '{"closeout_text":"Deployed the change."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "unknown adapter exit 0" "$RC" "0"

# ----------------------------------------------------------------
# Group 2: Phrase matching variants (8 tests)
# ----------------------------------------------------------------

# Test 6: default phrase "deployed" matches
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
PATH="$TMPDIR_MOCKS:$PATH"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"I have deployed v1.2.3 to production."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "deployed triggers phrase match" "$RECEIPT_BODY" '"matched_phrase":"deployed"'

# Test 7: "deployment complete" matches
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"deployment complete to staging."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "deployment complete triggers" "$RECEIPT_BODY" '"matched_phrase":"deployment complete"'

# Test 8: "shipped to production" matches
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"Shipped to production successfully."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "shipped to production triggers" "$RECEIPT_BODY" '"matched_phrase":"shipped to production"'

# Test 9: "rolled out" matches
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"Rolled out the change to all replicas."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "rolled out triggers" "$RECEIPT_BODY" '"matched_phrase":"rolled out"'

# Test 10: custom phrase list overrides default
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
export DRG_PHRASE_LIST="released,published"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"Released v2.0 to all users."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "custom phrase released matches" "$RECEIPT_BODY" '"matched_phrase":"released"'

# Test 11: default phrase NOT matching with custom list
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
export DRG_PHRASE_LIST="released,published"
OUT=$(echo '{"closeout_text":"I have deployed the change."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "default phrase not in custom list" "$RC" "0"
RECEIPT_COUNT=$(find "$DRG_RECEIPT_DIR" -name '*.jsonl' 2>/dev/null | wc -l)
if [ "$RECEIPT_COUNT" = "0" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: deployed matched against custom list"; fi

# Test 12: case-insensitive phrase match
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"DEPLOYED to production."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "case-insensitive phrase match" "$RECEIPT_BODY" '"matched_phrase":"deployed"'

# Test 13: phrase as part of larger word does NOT cause false-positive on exact form
# (current implementation uses fixed-string grep -F, partial match is intended)
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"I am redeployed and ready."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
# "deployed" is substring of "redeployed" — current behavior matches, documented behavior
assert_contains "substring match documented" "$RECEIPT_BODY" '"matched_phrase":"deployed"'

# ----------------------------------------------------------------
# Group 3: gh adapter behavior (5 tests)
# ----------------------------------------------------------------

# Test 14: gh adapter with matching sha → execute
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc123def4567890"}]'
OUT=$(echo '{"closeout_text":"Deployed abc123d to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "matching sha execute" "$RC" "0"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "decision execute on match" "$RECEIPT_BODY" '"decision":"execute"'

# Test 15: gh adapter with version mismatch → refuse
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"differentsha123"}]'
OUT=$(echo '{"closeout_text":"Deployed abc123def to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "mismatch exit 2" "$RC" "2"
assert_contains "mismatch message" "$OUT" "BLOCKED"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "decision refuse-mismatch" "$RECEIPT_BODY" '"decision":"refuse-mismatch"'

# Test 16: gh adapter with no DRG_GH_REPO + strict mode → refuse-query-failure
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_STRICT_MODE=1
OUT=$(echo '{"closeout_text":"Deployed v1.2.3 to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing GH_REPO strict refuse" "$RC" "2"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "query-failure recorded" "$RECEIPT_BODY" '"decision":"refuse-query-failure"'

# Test 17: gh adapter query failure + non-strict mode → execute (receipt only)
reset_env; reset_receipts
export DRG_ADAPTER="gh"
# DRG_GH_REPO unset
OUT=$(echo '{"closeout_text":"Deployed v1.2.3 to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "non-strict query-failure execute" "$RC" "0"

# Test 18: gh adapter with empty deployment list (query returns nothing)
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[]'
OUT=$(echo '{"closeout_text":"Deployed v1.2.3 to production."}' | bash "$HOOK" 2>&1)
RC=$?
# Non-strict default: query failure → execute
assert_exit "empty deployment list non-strict execute" "$RC" "0"

# ----------------------------------------------------------------
# Group 4: kubectl adapter behavior (4 tests)
# ----------------------------------------------------------------

# Test 19: kubectl adapter with matching revision → execute
reset_env; reset_receipts
export DRG_ADAPTER="kubectl"
export DRG_KUBECTL_NAMESPACE="production"
export DRG_KUBECTL_DEPLOYMENT="api"
make_mock kubectl 0 '42'
OUT=$(echo '{"closeout_text":"Rolled out v42 to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "kubectl match execute" "$RC" "0"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "kubectl adapter recorded" "$RECEIPT_BODY" '"adapter":"kubectl"'
assert_contains "kubectl target recorded" "$RECEIPT_BODY" '"target":"production/api"'

# Test 20: kubectl adapter with version mismatch → refuse
reset_env; reset_receipts
export DRG_ADAPTER="kubectl"
export DRG_KUBECTL_NAMESPACE="production"
export DRG_KUBECTL_DEPLOYMENT="api"
make_mock kubectl 0 '99'
OUT=$(echo '{"closeout_text":"Rolled out v42 to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "kubectl mismatch refuse" "$RC" "2"

# Test 21: kubectl adapter missing namespace → query failure
reset_env; reset_receipts
export DRG_ADAPTER="kubectl"
export DRG_KUBECTL_DEPLOYMENT="api"
export DRG_STRICT_MODE=1
OUT=$(echo '{"closeout_text":"Deployed v1 to prod."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "kubectl missing ns refuse" "$RC" "2"

# Test 22: kubectl adapter missing deployment → query failure
reset_env; reset_receipts
export DRG_ADAPTER="kubectl"
export DRG_KUBECTL_NAMESPACE="production"
export DRG_STRICT_MODE=1
OUT=$(echo '{"closeout_text":"Deployed v1 to prod."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "kubectl missing deployment refuse" "$RC" "2"

# ----------------------------------------------------------------
# Group 5: terraform adapter behavior (3 tests)
# ----------------------------------------------------------------

# Test 23: terraform adapter with matching output → execute
reset_env; reset_receipts
export DRG_ADAPTER="terraform"
export DRG_TERRAFORM_OUTPUT="release_version"
make_mock terraform 0 'v1.5.0'
OUT=$(echo '{"closeout_text":"Deployed v1.5.0 to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "terraform match execute" "$RC" "0"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "terraform target recorded" "$RECEIPT_BODY" '"target":"terraform-output:release_version"'

# Test 24: terraform adapter with version mismatch → refuse
reset_env; reset_receipts
export DRG_ADAPTER="terraform"
export DRG_TERRAFORM_OUTPUT="release_version"
make_mock terraform 0 'v2.0.0'
OUT=$(echo '{"closeout_text":"Deployed v1.5.0 to production."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "terraform mismatch refuse" "$RC" "2"

# Test 25: terraform adapter missing output name + strict → refuse-query-failure
reset_env; reset_receipts
export DRG_ADAPTER="terraform"
export DRG_STRICT_MODE=1
OUT=$(echo '{"closeout_text":"Deployed v1 to prod."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "terraform missing output strict refuse" "$RC" "2"

# ----------------------------------------------------------------
# Group 6: BYPASS overrides refuse (3 tests)
# ----------------------------------------------------------------

# Test 26: BYPASS=1 overrides refuse-mismatch
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
export DRG_BYPASS=1
make_mock gh 0 '[{"sha":"differentsha123"}]'
OUT=$(echo '{"closeout_text":"Deployed abc123def to prod."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "bypass overrides refuse-mismatch" "$RC" "0"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "bypass recorded in receipt" "$RECEIPT_BODY" '"decision":"execute-bypassed"'

# Test 27: BYPASS=1 overrides refuse-query-failure in strict mode
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_STRICT_MODE=1
export DRG_BYPASS=1
OUT=$(echo '{"closeout_text":"Deployed v1 to prod."}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "bypass overrides strict query-failure" "$RC" "0"
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "bypass on query-failure recorded" "$RECEIPT_BODY" '"decision":"execute-bypassed"'

# Test 28: BYPASS=1 with execute decision does NOT change to bypassed
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
export DRG_BYPASS=1
make_mock gh 0 '[{"sha":"abc123def"}]'
OUT=$(echo '{"closeout_text":"Deployed abc123d to prod."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "bypass does not affect execute" "$RECEIPT_BODY" '"decision":"execute"'

# ----------------------------------------------------------------
# Group 7: Receipt schema and audit trail (5 tests)
# ----------------------------------------------------------------

# Test 29: receipt is written to date-stamped file
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc"}]'
OUT=$(echo '{"closeout_text":"Deployed abc to prod."}' | bash "$HOOK" 2>&1)
EXPECTED_FILE="deployment-readback-$(date +%Y-%m-%d).jsonl"
if [ -f "$DRG_RECEIPT_DIR/$EXPECTED_FILE" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt date-stamped file"; fi

# Test 30: receipt has all required fields
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc"}]'
OUT=$(echo '{"closeout_text":"Deployed abc to prod."}' | bash "$HOOK" 2>&1)
RECEIPT_BODY=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null)
assert_contains "receipt has ts" "$RECEIPT_BODY" '"ts":"'
assert_contains "receipt has adapter" "$RECEIPT_BODY" '"adapter":"'
assert_contains "receipt has target" "$RECEIPT_BODY" '"target":"'
assert_contains "receipt has decision" "$RECEIPT_BODY" '"decision":"'
assert_contains "receipt has matched_phrase" "$RECEIPT_BODY" '"matched_phrase":"'
assert_contains "receipt has claimed_version" "$RECEIPT_BODY" '"claimed_version":"'
assert_contains "receipt has queried_version" "$RECEIPT_BODY" '"queried_version":"'

# Test 31: multiple receipts accumulate (JSONL append)
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc"}]'
echo '{"closeout_text":"Deployed v1 to prod."}' | bash "$HOOK" 2>&1 >/dev/null
echo '{"closeout_text":"Deployed v2 to staging."}' | bash "$HOOK" 2>&1 >/dev/null
RECEIPT_COUNT=$(cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null | wc -l)
if [ "$RECEIPT_COUNT" = "2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: 2 receipts expected, got $RECEIPT_COUNT"; fi

# Test 32: receipt is valid JSON per line
reset_env; reset_receipts
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc"}]'
echo '{"closeout_text":"Deployed abc to prod."}' | bash "$HOOK" 2>&1 >/dev/null
if cat "$DRG_RECEIPT_DIR"/*.jsonl 2>/dev/null | jq empty 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt not valid JSON"; fi

# Test 33: receipt directory is created if missing
reset_env
CUSTOM_DIR=$(mktemp -d)/nested/path
export DRG_RECEIPT_DIR="$CUSTOM_DIR"
export DRG_ADAPTER="gh"
export DRG_GH_REPO="x/y"
make_mock gh 0 '[{"sha":"abc"}]'
echo '{"closeout_text":"Deployed abc to prod."}' | bash "$HOOK" 2>&1 >/dev/null
if [ -d "$CUSTOM_DIR" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: receipt dir not created"; fi
rm -rf "$(dirname "$CUSTOM_DIR")" 2>/dev/null
export DRG_RECEIPT_DIR="$TMPDIR_RECEIPTS"

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------

echo ""
echo "================================"
echo "Tests: $((PASS + FAIL))"
echo "Pass:  $PASS"
echo "Fail:  $FAIL"
echo "================================"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
