#!/bin/bash
# Tests for subagent-identity-leak-guard.sh (Issue #55488 prevention)
HOOK="examples/subagent-identity-leak-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: Empty prompt should silently pass
OUT=$(echo '{"tool_input":{"prompt":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty prompt no warning" "$OUT" "Subagent identity boundary"
assert_exit "empty prompt exit 0" "$RC" "0"

# Test 2: Vague prompt should warn on all 3 checks
OUT=$(echo '{"tool_input":{"prompt":"please investigate the auth flow"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "vague prompt warns role" "$OUT" "No explicit role assignment"
assert_contains "vague prompt warns impersonation" "$OUT" "No prohibition against impersonating"
assert_contains "vague prompt warns history" "$OUT" "No prohibition against exposing"
assert_contains "vague prompt references issue" "$OUT" "#55488"
assert_exit "vague prompt exit 0 advisory" "$RC" "0"

# Test 3: Role assignment present, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"You are the backend agent. Investigate src/auth/login.ts."}}' | bash "$HOOK" 2>&1)
assert_not_contains "role only no role warning" "$OUT" "No explicit role"
assert_contains "role only warns impersonation" "$OUT" "No prohibition against impersonating"
assert_contains "role only warns history" "$OUT" "No prohibition against exposing"

# Test 4: Impersonation prohibition present, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Do not identify as the parent. Do something useful."}}' | bash "$HOOK" 2>&1)
assert_contains "impersonation only warns role" "$OUT" "No explicit role"
assert_not_contains "impersonation only no impersonation warning" "$OUT" "No prohibition against impersonating"
assert_contains "impersonation only warns history" "$OUT" "No prohibition against exposing"

# Test 5: History prohibition present, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Do not share the parent agent conversation history. Run a task."}}' | bash "$HOOK" 2>&1)
assert_contains "history only warns role" "$OUT" "No explicit role"
assert_contains "history only warns impersonation" "$OUT" "No prohibition against impersonating"
assert_not_contains "history only no history warning" "$OUT" "No prohibition against exposing"

# Test 6: All 3 boundary instructions present, no warning
OUT=$(echo '{"tool_input":{"prompt":"You are the backend agent. Do not identify as the parent or team-lead. Do not share the parent main agent conversation history. Investigate src/auth/login.ts."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "well-formed no warning" "$OUT" "Subagent identity boundary"
assert_exit "well-formed exit 0" "$RC" "0"

# Test 7: Strict mode (CC_SUBAGENT_IDENTITY_REQUIRE_ALL=1) blocks vague prompts
OUT=$(echo '{"tool_input":{"prompt":"investigate something"}}' | CC_SUBAGENT_IDENTITY_REQUIRE_ALL=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "strict mode warns" "$OUT" "Subagent identity boundary"
assert_exit "strict mode blocks (exit 2)" "$RC" "2"

# Test 8: Missing prompt field should silently pass
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "missing prompt no warning" "$OUT" "Subagent identity boundary"
assert_exit "missing prompt exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
