#!/bin/bash
# Tests for evidence-claim-gate.sh
#
# Verifies the Stop-hook behavior for epistemic-claim gating:
#   - Evidence claim without evidence-gathering tool → exit 2, stderr feedback
#   - Evidence claim with test-runner in same turn → exit 0 silent
#   - Evidence claim with read/grep in same turn → exit 0 silent
#   - Negation/disclosed-unverified form → exit 0 silent (operator informed)
#   - No evidence claim → exit 0 silent
#   - Missing assistant text → exit 0 silent (no false-positive)
#   - Future/passive forms not matched ("needs to be tested" → silent)
#   - Disable flag respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/evidence-claim-gate.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== evidence-claim-gate.sh tests ==="

# --- Test 1: "I tested" + no evidence command → blocks ---
INPUT=$(jq -nc '{
    transcript: [{content: "I tested the migration and it works."}],
    turn_tool_calls: [{command: "git add ."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "EVIDENCE CLAIM WITHOUT EVIDENCE"; then
    assert_pass "blocks 'I tested' without evidence (exit 2 + feedback)"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc output=$output"
fi

# --- Test 2: "tests pass" + npm test in same turn → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "All tests pass."}],
    turn_tool_calls: [{command: "npm test"}, {command: "git status"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'tests pass' with npm test is silent (exit 0)"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 3: "I verified that" + grep in same turn → silent (inspection counts) ---
INPUT=$(jq -nc '{
    transcript: [{content: "I verified that the function is unused."}],
    turn_tool_calls: [{command: "grep -rn unused_func ."}, {command: "ls"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'verified that' with grep evidence is silent"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 4: "I confirmed the schema" + Read tool → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "I confirmed the schema matches the migration."}, {}],
    turn_tool_calls: [{tool_name: "Read"}]
}')
# Use the last entry pattern that includes tool_calls
INPUT=$(jq -nc '{
    transcript: [{content: "I confirmed the schema matches the migration.", tool_calls: [{name: "Read", input: {file_path: "/foo"}}]}],
    turn_tool_calls: [{tool_name: "Read"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'I confirmed' with Read tool is silent"
else
    assert_fail "expected silent exit 0 (Read counts), got rc=$rc output=$output"
fi

# --- Test 5: no evidence claim → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "Investigating the failing test now."}],
    turn_tool_calls: [{command: "ls"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no evidence claim is silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 6: disclosed unverified form ("not yet tested") → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "The code is not yet tested. I need to add tests."}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'not yet tested' (disclosed unverified) is silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 7: future-tense form ("needs to be tested") → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "This function needs to be tested before deployment."}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'needs to be tested' (future form) is silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 8: passive-modal form ("should be verified") → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "This should be verified before merging."}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'should be verified' (passive modal) is silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 9: matches multiple evidence claim variants ---
for phrase in "I tested" "I have tested" "I've tested" "I verified" "I confirmed" "I validated" "I checked"; do
    INPUT=$(jq -nc --arg p "$phrase" '{
        transcript: [{content: ($p + " the implementation.")}],
        turn_tool_calls: []
    }')
    output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
    rc=$?
    if [ "$rc" -eq 2 ]; then
        assert_pass "evidence claim '$phrase' triggers gate"
    else
        assert_fail "evidence claim '$phrase' did NOT trigger (rc=$rc)"
    fi
done

# --- Test 10: "all tests pass" triggers without test runner ---
INPUT=$(jq -nc '{
    transcript: [{content: "All tests pass and the deploy is ready."}],
    turn_tool_calls: [{command: "git add ."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "'all tests pass' triggers without test runner"
else
    assert_fail "'all tests pass' should trigger, got rc=$rc"
fi

# --- Test 11: pytest counts as evidence command ---
INPUT=$(jq -nc '{
    transcript: [{content: "I tested it with pytest."}],
    turn_tool_calls: [{command: "pytest tests/"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'I tested' + pytest is silent"
else
    assert_fail "pytest should satisfy, got rc=$rc"
fi

# --- Test 12: playwright counts as evidence command ---
INPUT=$(jq -nc '{
    transcript: [{content: "I verified the login flow."}],
    turn_tool_calls: [{command: "playwright test e2e/login.spec.ts"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'I verified' + playwright is silent"
else
    assert_fail "playwright should satisfy, got rc=$rc"
fi

# --- Test 13: curl localhost counts ---
INPUT=$(jq -nc '{
    transcript: [{content: "I confirmed the endpoint returns 200."}],
    turn_tool_calls: [{command: "curl -i http://localhost:3000/api/health"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'I confirmed' + curl localhost is silent"
else
    assert_fail "curl localhost should satisfy, got rc=$rc"
fi

# --- Test 14: missing assistant text → silent (no false-positive) ---
INPUT=$(jq -nc '{
    transcript: [],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing assistant text is silent no-op"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 15: disable flag respected ---
INPUT=$(jq -nc '{
    transcript: [{content: "I tested it and it works."}],
    turn_tool_calls: []
}')
output=$(CC_EVIDENCE_GATE_DISABLE=1 printf '%s' "$INPUT" | CC_EVIDENCE_GATE_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_EVIDENCE_GATE_DISABLE=1 disables gate"
else
    assert_fail "disable flag not respected, got rc=$rc output=$output"
fi

# --- Test 16: custom CLAIMS regex ---
INPUT=$(jq -nc '{
    transcript: [{content: "I scrutinized the migration carefully."}],
    turn_tool_calls: []
}')
output=$(CC_EVIDENCE_CLAIMS='\bi[[:space:]]+scrutinized\b' printf '%s' "$INPUT" | CC_EVIDENCE_CLAIMS='\bi[[:space:]]+scrutinized\b' bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "custom CC_EVIDENCE_CLAIMS triggers correctly"
else
    assert_fail "custom regex should trigger, got rc=$rc"
fi

# --- Test 17: empty input → silent (graceful exit) ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty stdin is silent no-op"
else
    assert_fail "empty stdin should be silent, got rc=$rc output=$output"
fi

# --- Test 18: "verified that" form (no "I") triggers ---
INPUT=$(jq -nc '{
    transcript: [{content: "Verified that the migration was applied."}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "'verified that' (no I prefix) triggers gate"
else
    assert_fail "'verified that' should trigger, got rc=$rc"
fi

# --- Test 19: cargo test counts as evidence command ---
INPUT=$(jq -nc '{
    transcript: [{content: "I tested the new module."}],
    turn_tool_calls: [{command: "cargo test --release"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'I tested' + cargo test is silent"
else
    assert_fail "cargo test should satisfy, got rc=$rc"
fi

# --- Test 20: go test counts as evidence command ---
INPUT=$(jq -nc '{
    transcript: [{content: "I confirmed the handlers work."}],
    turn_tool_calls: [{command: "go test ./..."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "'I confirmed' + go test is silent"
else
    assert_fail "go test should satisfy, got rc=$rc"
fi

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
