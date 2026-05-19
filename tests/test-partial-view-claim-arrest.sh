#!/bin/bash
# Tests for partial-view-claim-arrest.sh
#
# Verifies the Stop-hook behavior at the Read-tool partial-view boundary
# introduced by v2.1.145:
#   - Read result with PARTIAL view + whole-file claim → exit 2 + reminder
#   - Read result with PARTIAL view + scoped claim → exit 0 silent
#   - Read result without PARTIAL marker → exit 0 silent
#   - No assistant text → exit 0 silent
#   - Disable flag respected
#   - Multiple PARTIAL marker variants recognized
#   - Multiple whole-file claim variants recognized

set -uo pipefail

HOOK="$(dirname "$0")/../examples/partial-view-claim-arrest.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== partial-view-claim-arrest.sh tests ==="

# --- Test 1: PARTIAL view + whole-file claim → blocks ---
INPUT=$(jq -nc '{
    transcript: [{content: "I reviewed the entire file and it looks good."}],
    turn_tool_calls: [{tool: "Read", result: "Lines 1-200 (PARTIAL view, file truncated):\n..."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "PARTIAL VIEW WITHOUT SCOPING"; then
    assert_pass "PARTIAL view + whole-file claim blocks with reminder"
else
    assert_fail "expected rc=2 + reminder, got rc=$rc output=$output"
fi

# --- Test 2: PARTIAL view + scoped claim → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "The first 200 lines of this file include the imports and class skeleton."}],
    turn_tool_calls: [{tool: "Read", result: "Lines 1-200 (PARTIAL view, file truncated):\n..."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "PARTIAL view + scoped claim is silent"
else
    assert_fail "expected silent on scoped claim, got rc=$rc output=$output"
fi

# --- Test 3: No PARTIAL marker → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "I reviewed the entire file."}],
    turn_tool_calls: [{tool: "Read", result: "Lines 1-50:\nfull contents here..."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no PARTIAL marker is silent"
else
    assert_fail "expected silent without PARTIAL marker, got rc=$rc output=$output"
fi

# --- Test 4: PARTIAL but no whole-file claim → silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "Investigating the failing test in handler.ts."}],
    turn_tool_calls: [{tool: "Read", result: "(PARTIAL view): showing first 200 lines"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "PARTIAL without whole-file claim is silent"
else
    assert_fail "expected silent without claim, got rc=$rc output=$output"
fi

# --- Test 5: alternative PARTIAL markers recognized ---
for marker in "truncated first page" "exceeds the token limit" "<PARTIAL>" "file truncated to 200 lines"; do
    INPUT=$(jq -nc --arg m "$marker" '{
        transcript: [{content: "The entire file passes the test."}],
        turn_tool_calls: [{tool: "Read", result: $m}]
    }')
    rc=$(printf '%s' "$INPUT" | bash "$HOOK" >/dev/null 2>&1; echo $?)
    if [ "$rc" -eq 2 ]; then
        assert_pass "marker variant '$marker' triggers gate"
    else
        assert_fail "marker variant '$marker' did not trigger (rc=$rc)"
    fi
done

# --- Test 6: alternative whole-file claim phrasings recognized ---
for claim in \
    "I reviewed the entire file" \
    "the whole file is correct" \
    "examined the complete contents" \
    "all of the imports are accounted for" \
    "the file contains everything we need" \
    "nothing else exists in the file" \
    "the file has been fully reviewed" ; do
    INPUT=$(jq -nc --arg c "$claim" '{
        transcript: [{content: $c}],
        turn_tool_calls: [{tool: "Read", result: "PARTIAL view: first page only"}]
    }')
    rc=$(printf '%s' "$INPUT" | bash "$HOOK" >/dev/null 2>&1; echo $?)
    if [ "$rc" -eq 2 ]; then
        assert_pass "claim phrasing '$claim' triggers gate"
    else
        assert_fail "claim phrasing '$claim' did not trigger (rc=$rc)"
    fi
done

# --- Test 7: missing assistant text → silent ---
INPUT='{"turn_tool_calls":[{"tool":"Read","result":"PARTIAL view"}]}'
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing assistant text is silent no-op"
else
    assert_fail "expected silent on missing text, got rc=$rc output=$output"
fi

# --- Test 8: empty input → silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input is silent no-op"
else
    assert_fail "expected silent on empty, got rc=$rc output=$output"
fi

# --- Test 9: CC_PARTIAL_VIEW_DISABLE=1 respected ---
INPUT=$(jq -nc '{
    transcript: [{content: "I reviewed the entire file"}],
    turn_tool_calls: [{tool: "Read", result: "PARTIAL view"}]
}')
output=$(printf '%s' "$INPUT" | CC_PARTIAL_VIEW_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_PARTIAL_VIEW_DISABLE=1 disables the gate"
else
    assert_fail "disable flag not respected (rc=$rc output=$output)"
fi

# --- Test 10: reminder cites #60226 ---
INPUT=$(jq -nc '{
    transcript: [{content: "the entire file is now refactored"}],
    turn_tool_calls: [{tool: "Read", result: "PARTIAL view"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "#60226"; then
    assert_pass "reminder cites #60226"
else
    assert_fail "expected #60226 reference in reminder (got: $output)"
fi

# --- Test 11: reminder cites v2.1.145 ---
INPUT=$(jq -nc '{
    transcript: [{content: "the whole file is fixed"}],
    turn_tool_calls: [{tool: "Read", result: "PARTIAL view"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "v2.1.145"; then
    assert_pass "reminder cites v2.1.145 release"
else
    assert_fail "expected v2.1.145 reference in reminder"
fi

# --- Test 12: reminder offers two mitigations (read more, or scope) ---
INPUT=$(jq -nc '{
    transcript: [{content: "all of the imports"}],
    turn_tool_calls: [{tool: "Read", result: "PARTIAL view"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "Read the rest of the file" && echo "$output" | grep -q "Scope the claim"; then
    assert_pass "reminder offers both mitigations (read more / scope)"
else
    assert_fail "expected both mitigations in reminder"
fi

# --- Test 13: PARTIAL signal in alternative payload location (recent_tool_results) ---
INPUT=$(jq -nc '{
    last_assistant_message: "the whole module is now consistent",
    recent_tool_results: [{tool_name: "Read", result: "PARTIAL view at line 200"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "recent_tool_results payload shape is recognized"
else
    assert_fail "expected gate on recent_tool_results shape, got rc=$rc"
fi

# --- Test 14: PARTIAL detected via permissive whole-input fallback ---
# (Old/unknown shape where neither transcript nor turn_tool_calls have the
#  Read result structurally — the hook's fallback scans the whole input)
INPUT='{"some_key":"contains PARTIAL view text","other":"the entire file matches the spec"}'
# Need both signals: PARTIAL in input + claim in assistant text. Without
# a recognized assistant-text key, the hook exits silently. This test
# documents the silent-no-op behavior.
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "unknown payload shape exits silently (no false-positive)"
else
    assert_fail "expected silent on unknown shape, got rc=$rc"
fi

# --- Test 15: matched whole-file phrase echoed in reminder ---
INPUT=$(jq -nc '{
    transcript: [{content: "the complete module is wired up"}],
    turn_tool_calls: [{tool: "Read", result: "PARTIAL view"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -qi "complete module"; then
    assert_pass "matched whole-file phrase is echoed in the reminder"
else
    assert_fail "expected matched phrase echo in reminder (got: $output)"
fi

# --- Test 16: scoped phrasings do NOT trigger ---
for scoped in \
    "the first 200 lines of this file include the imports" \
    "based on the first page of the file" \
    "from what I have seen so far (partial view), the imports look standard" \
    "the visible portion of the file declares" ; do
    INPUT=$(jq -nc --arg c "$scoped" '{
        transcript: [{content: $c}],
        turn_tool_calls: [{tool: "Read", result: "PARTIAL view"}]
    }')
    rc=$(printf '%s' "$INPUT" | bash "$HOOK" >/dev/null 2>&1; echo $?)
    if [ "$rc" -eq 0 ]; then
        assert_pass "scoped phrasing '$scoped' does not trigger"
    else
        assert_fail "scoped phrasing '$scoped' false-positive (rc=$rc)"
    fi
done

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
