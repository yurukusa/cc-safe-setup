#!/bin/bash
# Tests for closure-word-verify-gate.sh
#
# Verifies the Stop-hook behavior from issue #60506:
#   - Closure word without verification command → exit 2, stderr feedback
#   - Closure word with verification command in same turn → exit 0 silent
#   - No closure word in turn → exit 0 silent
#   - Missing assistant text → exit 0 silent (no false-positive)
#   - Disable flag respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/closure-word-verify-gate.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_hook() {
    local input="$1"
    local extra_env="${2:-}"
    if [ -n "$extra_env" ]; then
        eval "$extra_env bash \"$HOOK\"" <<< "$input" 2>&1
    else
        printf '%s' "$input" | bash "$HOOK" 2>&1
    fi
}

echo "=== closure-word-verify-gate.sh tests ==="

# --- Test 1: closure word + no verification → blocks ---
INPUT=$(jq -nc '{
    transcript: [{content: "All set, the migration is done."}],
    turn_tool_calls: [{command: "git add ."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "CLOSURE WITHOUT VERIFICATION"; then
    assert_pass "blocks closure without verification (exit 2 + feedback)"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc output=$output"
fi

# --- Test 2: closure word + verification in same turn → exits 0 ---
INPUT=$(jq -nc '{
    transcript: [{content: "All tests pass, this is done."}],
    turn_tool_calls: [{command: "npm test"}, {command: "git add ."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "closure with verification is silent (exit 0)"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 3: no closure word → silent exit ---
INPUT=$(jq -nc '{
    transcript: [{content: "Investigating the failing test now."}],
    turn_tool_calls: [{command: "ls"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no closure word is a silent no-op"
else
    assert_fail "expected silent no-op, got rc=$rc output=$output"
fi

# --- Test 4: matches multiple closure variants ---
for word in "shipped" "complete" "production ready" "bitti" "finished" "all set"; do
    INPUT=$(jq -nc --arg w "$word" '{
        transcript: [{content: ("OK, the feature is " + $w + " now.")}],
        turn_tool_calls: []
    }')
    output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
    rc=$?
    if [ "$rc" -eq 2 ]; then
        assert_pass "closure variant '$word' triggers gate"
    else
        assert_fail "closure variant '$word' did not trigger (rc=$rc)"
    fi
done

# --- Test 5: missing assistant text → silent (no false-positive) ---
INPUT='{"turn_tool_calls":[]}'
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing assistant text is silent no-op"
else
    assert_fail "expected silent on missing text, got rc=$rc output=$output"
fi

# --- Test 6: CC_CLOSURE_GATE_DISABLE=1 respected ---
INPUT=$(jq -nc '{
    transcript: [{content: "Done!"}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | CC_CLOSURE_GATE_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_CLOSURE_GATE_DISABLE=1 disables the gate"
else
    assert_fail "disable flag not respected (rc=$rc output=$output)"
fi

# --- Test 7: stderr feedback references #60506 ---
INPUT=$(jq -nc '{
    transcript: [{content: "shipped the fix"}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "#60506"; then
    assert_pass "feedback cites #60506 for grounding"
else
    assert_fail "expected reference to #60506 in feedback (got: $output)"
fi

# --- Test 8: alternative verification commands recognized ---
for cmd in "pytest" "playwright test" "cargo test" "curl http://localhost:3000/health" "go test ./..."; do
    INPUT=$(jq -nc --arg c "$cmd" '{
        transcript: [{content: "All done now."}],
        turn_tool_calls: [{command: $c}]
    }')
    rc=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null; echo $?)
    if [ "$rc" -eq 0 ]; then
        assert_pass "verification command '$cmd' satisfies the gate"
    else
        assert_fail "verification command '$cmd' did not satisfy (rc=$rc)"
    fi
done

# --- Test 9: matched closure word echoed in feedback ---
INPUT=$(jq -nc '{
    transcript: [{content: "Cool, that is finished now."}],
    turn_tool_calls: []
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -qi "finished"; then
    assert_pass "feedback echoes the matched closure word"
else
    assert_fail "feedback did not echo the matched word (got: $output)"
fi

# --- Test 10: empty input is a silent no-op ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input is a silent no-op"
else
    assert_fail "empty input should be silent (rc=$rc output=$output)"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
