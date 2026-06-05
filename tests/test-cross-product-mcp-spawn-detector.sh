#!/bin/bash
# Tests for cross-product-mcp-spawn-detector.sh (Issue #58806 prevention)
HOOK="examples/cross-product-mcp-spawn-detector.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Build a fake cross-product root for the test session.
TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t cc-xprod)
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

# Helper: write a fake .mcp.json with a plugin spawn config.
make_mcp_json() {
    local dir="$1"; local plugin_name="$2"
    mkdir -p "$dir"
    cat > "$dir/.mcp.json" <<JSON
{
  "${plugin_name}-mcp-server": {
    "command": "npx",
    "args": ["-y", "mcp-remote@latest", "https://mcp.${plugin_name}.example/mcp"]
  }
}
JSON
}

# Test 1: No blocklist set — hook exits 0 silently.
unset CC_CROSS_PRODUCT_BLOCKLIST CC_CROSS_PRODUCT_REQUIRE_CLEAN CC_CROSS_PRODUCT_EXTRA_ROOTS
OUT=$(bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no blocklist no output" "$OUT" "Cross-product"
assert_exit "no blocklist exit 0" "$RC" "0"

# Test 2: Blocklist set but no matching .mcp.json present — exit 0 silently.
SCAN_ROOT="$TMPROOT/empty"
mkdir -p "$SCAN_ROOT"
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble,wix" CC_CROSS_PRODUCT_EXTRA_ROOTS="$SCAN_ROOT" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty root no warning" "$OUT" "Cross-product"
assert_exit "empty root exit 0" "$RC" "0"

# Test 3: Blocklist matches a .mcp.json — warning emitted, exit 0 (advisory).
make_mcp_json "$TMPROOT/match/sess-1/sess-2/rpm/plugin_X" "nimble"
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble,wix" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/match" bash "$HOOK" 2>&1)
RC=$?
assert_contains "match warns" "$OUT" "Cross-product MCP spawn config"
assert_contains "match names plugin" "$OUT" "nimble"
assert_contains "match shows path" "$OUT" ".mcp.json"
assert_contains "match cites issue" "$OUT" "#58806"
assert_exit "match exit 0 advisory" "$RC" "0"

# Test 4: Strict mode CC_CROSS_PRODUCT_REQUIRE_CLEAN=1 blocks the session.
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/match" CC_CROSS_PRODUCT_REQUIRE_CLEAN=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "strict mode still warns" "$OUT" "Cross-product MCP spawn"
assert_exit "strict mode exit 2" "$RC" "2"

# Test 5: Multiple plugins in blocklist, only one matches — match wins, exit 0.
make_mcp_json "$TMPROOT/multi/sess-A/sess-B/rpm/plugin_Y" "serena"
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble
wix
serena" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/multi" bash "$HOOK" 2>&1)
RC=$?
assert_contains "multi match serena" "$OUT" "serena"
assert_not_contains "multi no false wix" "$OUT" "blocked plugin 'wix'"
assert_exit "multi exit 0" "$RC" "0"

# Test 6: Blocked plugin substring should not match a different plugin name.
# A .mcp.json containing "trusted-foo" must not match a blocklist of "foo" — wait,
# this hook uses grep -F (literal substring), so "foo" WILL match "trusted-foo".
# That is intentional — operator chooses blocklist precision. Test the negative
# case where the substring is not present at all.
make_mcp_json "$TMPROOT/negative/sess/sub" "totally-different-name"
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/negative" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no substring no warning" "$OUT" "Cross-product"
assert_exit "no substring exit 0" "$RC" "0"

# Test 7: Multiple extra roots scanned, each with its own match.
make_mcp_json "$TMPROOT/root1/x/y" "alpha"
make_mcp_json "$TMPROOT/root2/p/q" "beta"
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="alpha,beta" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/root1
$TMPROOT/root2" bash "$HOOK" 2>&1)
RC=$?
assert_contains "multi-root alpha" "$OUT" "alpha"
assert_contains "multi-root beta" "$OUT" "beta"
assert_exit "multi-root exit 0" "$RC" "0"

# Test 8: Whitespace tolerance in blocklist (spaces around names).
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="  nimble  ,  wix  " CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/match" bash "$HOOK" 2>&1)
RC=$?
assert_contains "trimmed blocklist matches" "$OUT" "nimble"
assert_exit "trimmed exit 0" "$RC" "0"

# Test 9: Non-existent extra root should not error out.
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/does/not/exist" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "missing root no warning" "$OUT" "Cross-product"
assert_exit "missing root exit 0" "$RC" "0"

# Test 10: Mitigation guidance is present in the warning text.
OUT=$(CC_CROSS_PRODUCT_BLOCKLIST="nimble" CC_CROSS_PRODUCT_EXTRA_ROOTS="$TMPROOT/match" bash "$HOOK" 2>&1)
assert_contains "mitigation MCP_REMOTE_NO_OPEN" "$OUT" "MCP_REMOTE_NO_OPEN=1"
assert_contains "mitigation PreToolUse" "$OUT" "PreToolUse"
assert_contains "mitigation remove" "$OUT" "Remove the .mcp.json"

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
