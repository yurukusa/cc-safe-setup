#!/bin/bash
# Tests for partial-view-claim-arrest.sh
#
# Verifies the Stop-hook behavior for the v2.1.145 PARTIAL view soft-upgrade
# failure surface:
#   - PARTIAL view notice + whole-file claim → exit 2, stderr feedback
#   - PARTIAL view notice + scoped phrasing → exit 0 silent (correctly scoped)
#   - PARTIAL view notice + no whole-file claim → exit 0 silent
#   - No PARTIAL view notice → exit 0 silent (no Read of that kind)
#   - Missing assistant text → exit 0 silent (no false-positive)
#   - Disable flag respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/partial-view-claim-arrest.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== partial-view-claim-arrest.sh tests ==="

# --- Test 1: PARTIAL view + whole-file claim → blocks ---
INPUT=$(jq -nc '{
    transcript: [{content: "I read the entire file and the imports look correct."}],
    turn_tool_results: [{content: "PARTIAL view: file truncated at line 100"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "PARTIAL VIEW + WHOLE-FILE CLAIM"; then
    assert_pass "blocks PARTIAL view + whole-file claim (exit 2 + feedback)"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc"
fi

# --- Test 2: PARTIAL view + scoped phrasing → exits 0 ---
INPUT=$(jq -nc '{
    transcript: [{content: "Based on the first page, the imports look correct. Need to read the rest of the file."}],
    turn_tool_results: [{content: "PARTIAL view: file truncated at line 100"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 when claim is scoped (based on first page)"
else
    assert_fail "expected exit 0, got rc=$rc output=$output"
fi

# --- Test 3: PARTIAL view + first-N-lines scoped → exits 0 ---
INPUT=$(jq -nc '{
    transcript: [{content: "The first 100 lines of the file contain only the imports."}],
    turn_tool_results: [{content: "PARTIAL view: showing first 100 lines of 500"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 when scoped to 'first N lines'"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 4: PARTIAL view + no whole-file claim → exits 0 ---
INPUT=$(jq -nc '{
    transcript: [{content: "Got the imports section."}],
    turn_tool_results: [{content: "PARTIAL view: file truncated"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 when no whole-file claim made"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 5: No PARTIAL view notice → exits 0 silent ---
INPUT=$(jq -nc '{
    transcript: [{content: "I read the entire file and there are 12 functions."}],
    turn_tool_results: [{content: "Successfully read all 250 lines of the file"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 when no PARTIAL view notice (full read)"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 6: Missing assistant text → exits 0 silent ---
INPUT='{}'
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 silent when assistant text missing (no false-positive)"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 7: Empty input → exits 0 silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 silent on empty input"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 8: Disable flag respected ---
INPUT=$(jq -nc '{
    transcript: [{content: "I read the entire file."}],
    turn_tool_results: [{content: "PARTIAL view: truncated"}]
}')
output=$(CC_PARTIAL_GATE_DISABLE=1 printf '%s' "$INPUT" | CC_PARTIAL_GATE_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 when CC_PARTIAL_GATE_DISABLE=1"
else
    assert_fail "expected exit 0 with disable flag, got rc=$rc"
fi

# --- Test 9: Alternative notice form (truncated first page) ---
INPUT=$(jq -nc '{
    transcript: [{content: "All of the imports are present."}],
    turn_tool_results: [{content: "Returned a truncated first page; file is 500 lines."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "WHOLE-FILE CLAIM"; then
    assert_pass "detects alternative notice form (truncated first page)"
else
    assert_fail "expected exit 2 for truncated-first-page form, got rc=$rc"
fi

# --- Test 10: Alternative claim form (every function in the file) ---
INPUT=$(jq -nc '{
    transcript: [{content: "Every function in the file uses async/await."}],
    turn_tool_results: [{content: "PARTIAL view: showing first 50 lines of 800"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "detects 'every function in the file' as whole-file claim"
else
    assert_fail "expected exit 2 for 'every function in the file', got rc=$rc"
fi

# --- Test 11: Reviewed-the-entire phrasing ---
INPUT=$(jq -nc '{
    transcript: [{content: "Reviewed the entire codebase already, ready to refactor."}],
    turn_tool_results: [{content: "PARTIAL view: file truncated"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "detects 'reviewed the entire' as whole-file claim"
else
    assert_fail "expected exit 2 for 'reviewed the entire', got rc=$rc"
fi

# --- Test 12: Visible portion scoped phrasing ---
INPUT=$(jq -nc '{
    transcript: [{content: "In the visible portion of the file I see 4 functions; need to read past line 100 to see the rest."}],
    turn_tool_results: [{content: "PARTIAL view: truncated"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 with 'visible portion' scoped phrasing"
else
    assert_fail "expected exit 0 with visible-portion scoping, got rc=$rc"
fi

# --- Test 13: Read tool result via alternative key (recent_tool_results) ---
INPUT=$(jq -nc '{
    transcript: [{content: "All of the imports look fine."}],
    recent_tool_results: ["PARTIAL view: showing first 80 lines"]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "detects PARTIAL view via recent_tool_results alternative key"
else
    assert_fail "expected exit 2 via alternative key, got rc=$rc"
fi

# --- Test 14: CC_PARTIAL_VIEW_NOTICES override ---
INPUT=$(jq -nc '{
    transcript: [{content: "All files were read."}],
    turn_tool_results: [{content: "[CUSTOM_TRUNCATED_MARKER]"}]
}')
output=$(CC_PARTIAL_VIEW_NOTICES='\[CUSTOM_TRUNCATED_MARKER\]' printf '%s' "$INPUT" | CC_PARTIAL_VIEW_NOTICES='\[CUSTOM_TRUNCATED_MARKER\]' bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "CC_PARTIAL_VIEW_NOTICES env var override works"
else
    assert_fail "expected exit 2 with custom notice, got rc=$rc"
fi

# --- Test 15: Scoped phrasing trumps even strong claim ---
INPUT=$(jq -nc '{
    transcript: [{content: "I read the entire file (only the first 100 lines are loaded so far; I need to read the rest)."}],
    turn_tool_results: [{content: "PARTIAL view: truncated"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "scoped phrasing in same response exempts the strong claim"
else
    assert_fail "expected exit 0 when scoped phrasing present, got rc=$rc"
fi

# --- Test 16: All files were read (multiple files claim) ---
INPUT=$(jq -nc '{
    transcript: [{content: "All files were read; the project structure is clear."}],
    turn_tool_results: [{content: "PARTIAL view: showing first 100 lines of 400"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "detects 'all files were read' as whole-file claim"
else
    assert_fail "expected exit 2 for all-files claim, got rc=$rc"
fi

# --- Test 17: Whole file phrase variation (the complete contents) ---
INPUT=$(jq -nc '{
    transcript: [{content: "I have the complete contents of the configuration."}],
    turn_tool_results: [{content: "PARTIAL view: truncated"}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "detects 'the complete contents' as whole-file claim"
else
    assert_fail "expected exit 2 for complete-contents claim, got rc=$rc"
fi

# --- Test 18: Only ASSISTANT_TEXT without tool_results → silent exit ---
INPUT=$(jq -nc '{
    transcript: [{content: "I read the entire file."}]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "exits 0 silent when no tool results provided (no false-positive)"
else
    assert_fail "expected exit 0 silent without tool results, got rc=$rc"
fi

# --- Test 19: Multiple PARTIAL view tool results in same turn ---
INPUT=$(jq -nc '{
    transcript: [{content: "The whole file has been processed correctly."}],
    turn_tool_results: [
      {content: "PARTIAL view: file A truncated"},
      {content: "Read file B fully, 50 lines"},
      {content: "PARTIAL view: file C truncated"}
    ]
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "fires when ANY same-turn tool result has PARTIAL view"
else
    assert_fail "expected exit 2 with multi-result PARTIAL view, got rc=$rc"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
