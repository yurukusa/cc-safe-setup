#!/bin/bash
# Tests for subagent-permission-mode-guard.sh (Issue #55691 prevention)
HOOK="examples/subagent-permission-mode-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: No mode parameter, silent pass
OUT=$(echo '{"tool_input":{"prompt":"do something"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no mode no warning" "$OUT" "Subagent permission mode"
assert_not_contains "no mode no early warn" "$OUT" "may be silently overridden"
assert_exit "no mode exit 0" "$RC" "0"

# Test 2: Mode parameter with no prompt
OUT=$(echo '{"tool_input":{"mode":"bypassPermissions","prompt":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "empty prompt with mode warns" "$OUT" "may be silently overridden"
assert_contains "empty prompt with mode references issue" "$OUT" "#55691"
assert_exit "empty prompt with mode exit 0" "$RC" "0"

# Test 3: Mode parameter with vague prompt warns 2 items
OUT=$(echo '{"tool_input":{"mode":"bypassPermissions","prompt":"please investigate the auth flow"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "vague warns frontmatter" "$OUT" "frontmatter override risk"
assert_contains "vague warns verification" "$OUT" "verification of the actual effective mode"
assert_contains "vague references issue" "$OUT" "#55691"
assert_exit "vague exit 0 advisory" "$RC" "0"

# Test 4: Frontmatter mention only
OUT=$(echo '{"tool_input":{"mode":"bypassPermissions","prompt":"check if the frontmatter has permissionMode and run."}}' | bash "$HOOK" 2>&1)
assert_not_contains "frontmatter only no frontmatter warning" "$OUT" "frontmatter override risk"
assert_contains "frontmatter only warns verification" "$OUT" "verification of the actual"

# Test 5: Verification mention only
OUT=$(echo '{"tool_input":{"mode":"bypassPermissions","prompt":"run the task and verify the mode is active."}}' | bash "$HOOK" 2>&1)
assert_contains "verify only warns frontmatter" "$OUT" "frontmatter override risk"
assert_not_contains "verify only no verify warning" "$OUT" "verification of the actual"

# Test 6: All instructions present, no warning
OUT=$(echo '{"tool_input":{"mode":"bypassPermissions","prompt":"check if the frontmatter has permissionMode set, then run the task and verify the effective permission is bypassPermissions."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "well-formed no warning" "$OUT" "Subagent permission mode boundary"
assert_exit "well-formed exit 0" "$RC" "0"

# Test 7: Strict mode blocks vague
OUT=$(echo '{"tool_input":{"mode":"bypassPermissions","prompt":"investigate something"}}' | CC_SUBAGENT_MODE_REQUIRE_ALL=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "strict mode warns" "$OUT" "Subagent permission mode boundary"
assert_exit "strict mode blocks (exit 2)" "$RC" "2"

# Test 8: Empty input, no mode
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty input no warning" "$OUT" "Subagent permission mode"
assert_exit "empty input exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
