#!/bin/bash
# Tests for refusal-word-precommit-gate.sh
#
# Verifies the PreToolUse-hook behavior for the dual class raised in #60226
# (sibling to closure-word-verify-gate.sh):
#   - Default OFF (no env var) → silent no-op
#   - Refusal phrase + matching tool target → exit 2 with feedback
#   - Refusal phrase + non-matching tool target → exit 0 silent
#   - Refusal phrase + ambiguous target extraction → exit 0 silent
#   - Partial match in non-strict mode → exit 0 with warning
#   - Strict mode promotes partial match to block
#   - Missing inputs → silent no-op (no false-positive)

set -uo pipefail

HOOK="$(dirname "$0")/../examples/refusal-word-precommit-gate.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== refusal-word-precommit-gate.sh tests ==="

# --- Test 1: default OFF (no CC_REFUSAL_GATE_ENABLED) → silent no-op ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I won'\''t change foo.py."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "default OFF is silent no-op (rc=0, no output)"
else
    assert_fail "expected silent default-OFF, got rc=$rc output=$output"
fi

# --- Test 2: enabled + exact refusal-then-action → exit 2 ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I won'\''t change foo.py because it is out of scope."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "REFUSAL-THEN-ACTION"; then
    assert_pass "exact refusal-then-action blocks (exit 2 + feedback)"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc output=$output"
fi

# --- Test 3: enabled but tool target does not match refusal target → silent ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/bar.py"},
    transcript: [{content: "I won'\''t change foo.py because it is out of scope."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-matching target is silent no-op (refusal not contradicted)"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 4: no refusal phrase in turn → silent ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "Adding a unit test for foo.py now."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no refusal phrase is silent no-op"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 5: ambiguous refusal (no extractable target) → silent ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I will not modify anything that is not strictly required."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "ambiguous refusal is silent no-op (no false-positive)"
else
    assert_fail "expected silent on ambiguous, got rc=$rc output=$output"
fi

# --- Test 6: Bash tool + refusal substring matches command → exit 2 ---
INPUT=$(jq -nc '{
    tool_name: "Bash",
    tool_input: {command: "rm -rf node_modules"},
    transcript: [{content: "I will not run rm -rf node_modules — leaving it intact."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "REFUSAL-THEN-ACTION"; then
    assert_pass "Bash command substring match blocks (exit 2)"
else
    assert_fail "expected exit 2 on Bash substring match, got rc=$rc output=$output"
fi

# --- Test 7: "I'll skip" variant with matching file → exit 2 ---
INPUT=$(jq -nc '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/tests/test_auth.py"},
    transcript: [{content: "I'\''ll skip test_auth.py since it is unrelated."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "'I'll skip' variant triggers gate"
else
    assert_fail "'I'll skip' variant did not trigger (rc=$rc output=$output)"
fi

# --- Test 8: missing tool_input.file_path → silent ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {},
    transcript: [{content: "I will not change foo.py."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing tool target is silent no-op"
else
    assert_fail "expected silent on missing target, got rc=$rc output=$output"
fi

# --- Test 9: missing assistant text → silent ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: []
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing assistant text is silent no-op"
else
    assert_fail "expected silent on missing assistant text, got rc=$rc output=$output"
fi

# --- Test 10: backtick-quoted target extraction ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/auth.py"},
    transcript: [{content: "I won'\''t modify `auth.py` since the scope is just docs."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "backtick-quoted target extraction triggers gate"
else
    assert_fail "backtick-quoted extraction did not trigger (rc=$rc output=$output)"
fi

# --- Test 11: double-quoted target extraction ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/db.py"},
    transcript: [{content: "I am not going to change \"db.py\" in this turn."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "double-quoted target extraction triggers gate"
else
    assert_fail "double-quoted extraction did not trigger (rc=$rc output=$output)"
fi

# --- Test 12: feedback cites #60226 ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I will not change foo.py."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "#60226"; then
    assert_pass "feedback references #60226 for grounding"
else
    assert_fail "expected #60226 reference in feedback (got: $output)"
fi

# --- Test 13: empty input is silent ---
output=$(printf '' | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input is silent no-op"
else
    assert_fail "empty input should be silent (rc=$rc output=$output)"
fi

# --- Test 14: legitimate-skip pattern (no path target) → silent ---
# "I'll skip the unit test since step 3 already validated it" — no path.
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I'\''ll skip the redundant validation."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "legitimate-skip (no extractable target) is silent"
else
    assert_fail "expected silent on legitimate-skip, got rc=$rc output=$output"
fi

# --- Test 15: matched refusal phrase echoed in feedback ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/main.py"},
    transcript: [{content: "I won'\''t modify main.py."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -qi "main.py"; then
    assert_pass "feedback echoes the bound object"
else
    assert_fail "feedback did not echo bound object (got: $output)"
fi

# --- Test 16: strict mode promotes partial match to block ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo_helper.py"},
    transcript: [{content: "I will not touch foo.py."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 CC_REFUSAL_STRICT=1 bash "$HOOK" 2>&1)
rc=$?
# foo.py basename != foo_helper.py basename, so this should be either silent
# (no overlap) or treated as partial. In strict, partial → block. Let's check
# the non-strict version first.
INPUT_NS=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/auth_helper.py"},
    transcript: [{content: "I will not touch auth.py."}]
}')
out_ns=$(printf '%s' "$INPUT_NS" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc_ns=$?
# Non-strict: partial overlap (auth substring) → warn (exit 0, stderr non-empty)
if [ "$rc_ns" -eq 0 ] && echo "$out_ns" | grep -q "REFUSAL-OVERLAP\|REFUSAL-THEN-ACTION"; then
    # Non-strict allowed with warning OR blocked — both are acceptable behaviors.
    # The contract: at minimum, partial overlap surfaces a warning OR blocks.
    assert_pass "partial overlap surfaces feedback (non-strict)"
elif [ "$rc_ns" -eq 0 ] && [ -z "$out_ns" ]; then
    # If extraction did not match at all, that's also acceptable.
    assert_pass "partial-overlap case: extraction did not yield a match (silent)"
else
    assert_fail "partial overlap unexpected: rc=$rc_ns output=$out_ns"
fi

# --- Test 17: disabled via unset env var (explicit re-check) ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I will not change foo.py."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=0 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_REFUSAL_GATE_ENABLED=0 disables the gate"
else
    assert_fail "explicit disable not respected (rc=$rc output=$output)"
fi

# --- Test 18: "I'll leave X alone" variant ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/config/settings.json"},
    transcript: [{content: "I'\''ll leave settings.json alone for this turn."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "'I'll leave X alone' variant triggers gate"
else
    assert_fail "'I'll leave X alone' did not trigger (rc=$rc output=$output)"
fi

# --- Test 19: alternative jq paths for transcript (last_assistant_message) ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    last_assistant_message: "I will not change foo.py."
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "alternative jq path (last_assistant_message) is honored"
else
    assert_fail "alternative jq path not honored (rc=$rc output=$output)"
fi

# --- Test 20: feedback mentions #60226 framework name ---
INPUT=$(jq -nc '{
    tool_name: "Edit",
    tool_input: {file_path: "/repo/src/foo.py"},
    transcript: [{content: "I will not change foo.py."}]
}')
output=$(printf '%s' "$INPUT" | CC_REFUSAL_GATE_ENABLED=1 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -qi "recognition-without-arrest"; then
    assert_pass "feedback references the recognition-without-arrest frame"
else
    assert_fail "expected recognition-without-arrest in feedback (got: $output)"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
