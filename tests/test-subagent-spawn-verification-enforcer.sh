#!/bin/bash
# Tests for subagent-spawn-verification-enforcer.sh (Issue #55666 prevention)
HOOK="examples/subagent-spawn-verification-enforcer.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: Empty prompt should silently pass
OUT=$(echo '{"tool_input":{"prompt":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty prompt no warning" "$OUT" "Subagent output verification"
assert_exit "empty prompt exit 0" "$RC" "0"

# Test 2: Vague prompt should warn on all 3 checks
OUT=$(echo '{"tool_input":{"prompt":"please investigate the auth flow"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "vague warns artifact" "$OUT" "No concrete artifact"
assert_contains "vague warns verification" "$OUT" "No artifact verification"
assert_contains "vague warns recommended" "$OUT" "Recommended:"
assert_contains "vague references issue" "$OUT" "#55666"
assert_exit "vague exit 0 advisory" "$RC" "0"

# Test 3: Artifact named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Write to /tmp/result.txt with the analysis."}}' | bash "$HOOK" 2>&1)
assert_not_contains "artifact only no artifact warning" "$OUT" "No concrete artifact"
assert_contains "artifact only warns verification" "$OUT" "No artifact verification"

# Test 4: Verification named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Investigate. I will verify the result."}}' | bash "$HOOK" 2>&1)
assert_contains "verify only warns artifact" "$OUT" "No concrete artifact"
assert_not_contains "verify only no verify warning" "$OUT" "No artifact verification"

# Test 5: Distrust phrase named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Do something. Do not trust reply-only success."}}' | bash "$HOOK" 2>&1)
assert_contains "distrust only warns artifact" "$OUT" "No concrete artifact"
assert_contains "distrust only warns verification" "$OUT" "No artifact verification"
assert_not_contains "distrust only no recommended warning" "$OUT" "Recommended:"

# Test 6: All 3 instructions present, no warning
OUT=$(echo '{"tool_input":{"prompt":"Write to /tmp/result.txt. I will verify the file exists. Do not reply success without producing the artifact."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "well-formed no warning" "$OUT" "Subagent output verification"
assert_exit "well-formed exit 0" "$RC" "0"

# Test 7: Strict mode blocks vague prompts
OUT=$(echo '{"tool_input":{"prompt":"investigate something"}}' | CC_SUBAGENT_VERIFY_REQUIRE_ALL=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "strict mode warns" "$OUT" "Subagent output verification"
assert_exit "strict mode blocks (exit 2)" "$RC" "2"

# Test 8: Missing prompt field should silently pass
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "missing prompt no warning" "$OUT" "Subagent output verification"
assert_exit "missing prompt exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
