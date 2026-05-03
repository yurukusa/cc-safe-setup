#!/bin/bash
# Tests for subagent-tool-allowlist-enforcer.sh (Issue #55653 prevention)
HOOK="examples/subagent-tool-allowlist-enforcer.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: Empty prompt should silently pass
OUT=$(echo '{"tool_input":{"prompt":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty prompt no warning" "$OUT" "Subagent tool boundary"
assert_exit "empty prompt exit 0" "$RC" "0"

# Test 2: Vague prompt should warn on all 3 checks
OUT=$(echo '{"tool_input":{"prompt":"please investigate the auth flow"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "vague warns allowed tools" "$OUT" "No allowed tool set"
assert_contains "vague warns forbidden tools" "$OUT" "No forbidden tools"
assert_contains "vague warns verification" "$OUT" "No parent verification"
assert_contains "vague references issue" "$OUT" "#55653"
assert_exit "vague exit 0 advisory" "$RC" "0"

# Test 3: Allowed tools named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"You can use Read and Grep. Investigate src/auth/login.ts."}}' | bash "$HOOK" 2>&1)
assert_not_contains "allowed only no allowed warning" "$OUT" "No allowed tool set"
assert_contains "allowed only warns forbidden" "$OUT" "No forbidden tools"
assert_contains "allowed only warns verification" "$OUT" "No parent verification"

# Test 4: Read-only constraint named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"This is read-only. Run a task."}}' | bash "$HOOK" 2>&1)
assert_contains "read-only only warns allowed" "$OUT" "No allowed tool set"
assert_not_contains "read-only only no forbidden warning" "$OUT" "No forbidden tools"
assert_contains "read-only only warns verification" "$OUT" "No parent verification"

# Test 5: Verification step named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Investigate something. I will verify with stat."}}' | bash "$HOOK" 2>&1)
assert_contains "verify only warns allowed" "$OUT" "No allowed tool set"
assert_contains "verify only warns forbidden" "$OUT" "No forbidden tools"
assert_not_contains "verify only no verification warning" "$OUT" "No parent verification"

# Test 6: All 3 boundary instructions present, no warning
OUT=$(echo '{"tool_input":{"prompt":"You can use Read and Grep. Do not write or edit any file. I will verify the result with file stat. Investigate src/auth/login.ts."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "well-formed no warning" "$OUT" "Subagent tool boundary"
assert_exit "well-formed exit 0" "$RC" "0"

# Test 7: Strict mode blocks vague prompts
OUT=$(echo '{"tool_input":{"prompt":"investigate something"}}' | CC_SUBAGENT_TOOL_REQUIRE_ALL=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "strict mode warns" "$OUT" "Subagent tool boundary"
assert_exit "strict mode blocks (exit 2)" "$RC" "2"

# Test 8: Missing prompt field should silently pass
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "missing prompt no warning" "$OUT" "Subagent tool boundary"
assert_exit "missing prompt exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
