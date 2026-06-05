#!/bin/bash
# Tests for examples/commitment-carry-forward-arrest.sh
# Defends row 7 of the recognition-without-arrest matrix
# (anthropics/claude-code#61388).

set -uo pipefail

HOOK="$(dirname "$0")/../examples/commitment-carry-forward-arrest.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export CC_COMMITMENT_LEDGER_DIR="$TEST_DIR"
export CC_SESSION_ID="test-session-abc"
SESSION_HASH=$(echo -n "test-session-abc" | sha256sum | cut -c1-16)
LEDGER="$TEST_DIR/outstanding-commitments-${SESSION_HASH}.jsonl"

PASS=0
FAIL=0
TESTS=()

assert_eq() {
    local name="$1"; local expected="$2"; local actual="$3"
    TESTS+=("$name")
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $name"
        PASS=$((PASS+1))
    else
        echo "FAIL: $name"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    local name="$1"; local needle="$2"; local haystack="$3"
    TESTS+=("$name")
    if echo "$haystack" | grep -qF "$needle"; then
        echo "PASS: $name"
        PASS=$((PASS+1))
    else
        echo "FAIL: $name"
        echo "  needle:   $needle"
        echo "  haystack: $haystack"
        FAIL=$((FAIL+1))
    fi
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK"
    return $?
}

# ============================================================
# Group 1: Syntax + dispatch
# ============================================================

echo "=== Group 1: Syntax + dispatch ==="

bash -n "$HOOK"
assert_eq "1.1 bash -n returns 0" "0" "$?"

# Unknown event: exit 0
INPUT='{"hook_event_name":"UnknownEvent"}'
run_hook "$INPUT" >/dev/null 2>&1
assert_eq "1.2 unknown event exits 0" "0" "$?"

# Empty event name: exit 0
INPUT='{"hook_event_name":""}'
run_hook "$INPUT" >/dev/null 2>&1
assert_eq "1.3 empty event exits 0" "0" "$?"

# ============================================================
# Group 2: Stop event — commitment extraction
# ============================================================

echo "=== Group 2: Stop event — commitment extraction ==="

rm -f "$LEDGER"

# Single commitment "I'll <verb>"
INPUT='{"hook_event_name":"Stop","response":"OK, I will push the changes after the tests run.","turn":1}'
run_hook "$INPUT" >/dev/null 2>&1
assert_eq "2.1 Stop with 'I will push' exits 0" "0" "$?"

if [ -f "$LEDGER" ]; then
    line_count=$(wc -l < "$LEDGER" || echo 0)
    [ "$line_count" -ge 1 ] && pass=true || pass=false
else
    pass=false
fi
[ "$pass" = "true" ] && actual=ok || actual=missing
assert_eq "2.2 ledger file created with at least 1 entry" "ok" "$actual"

# Multiple commitments in one response
rm -f "$LEDGER"
INPUT='{"hook_event_name":"Stop","response":"I will update the docs. Next, I will run the tests. Then I am going to verify the deployment.","turn":2}'
run_hook "$INPUT" >/dev/null 2>&1
line_count=$(wc -l < "$LEDGER" 2>/dev/null || echo 0)
[ "$line_count" -ge 2 ] && actual=ok || actual="$line_count"
assert_eq "2.3 multiple commitments produce multiple JSONL lines" "ok" "$actual"

# No commitment language → no entries
rm -f "$LEDGER"
INPUT='{"hook_event_name":"Stop","response":"The task is complete. The files have been written.","turn":3}'
run_hook "$INPUT" >/dev/null 2>&1
if [ -f "$LEDGER" ]; then
    line_count=$(wc -l < "$LEDGER" || echo 0)
else
    line_count=0
fi
assert_eq "2.4 no commitment language: ledger empty/missing" "0" "$line_count"

# ============================================================
# Group 3: Ledger format integrity
# ============================================================

echo "=== Group 3: Ledger format integrity ==="

rm -f "$LEDGER"
INPUT='{"hook_event_name":"Stop","response":"Got it. I will verify the merge after the CI passes.","turn":4}'
run_hook "$INPUT" >/dev/null 2>&1

if [ -f "$LEDGER" ]; then
    first_line=$(head -1 "$LEDGER")
    # JSON valid
    echo "$first_line" | python3 -m json.tool >/dev/null 2>&1
    assert_eq "3.1 ledger entry is valid JSON" "0" "$?"
    # Contains expected fields
    assert_contains "3.2 ledger has ts field" '"ts"' "$first_line"
    assert_contains "3.3 ledger has session_id field" '"session_id"' "$first_line"
    assert_contains "3.4 ledger has commitment_hash field" '"commitment_hash"' "$first_line"
    assert_contains "3.5 ledger has status open" '"status":"open"' "$first_line"
    assert_contains "3.6 ledger has byte_length field" '"byte_length"' "$first_line"
    # PHI-safety: commitment_summary should NOT contain "verify the merge" verbatim
    # raw text (since hash is 16-char prefix of sha256). The summary is the
    # matched verb-phrase string.
    assert_contains "3.7 ledger has commitment_summary" '"commitment_summary"' "$first_line"
fi

# ============================================================
# Group 4: PII masking
# ============================================================

echo "=== Group 4: PII masking ==="

rm -f "$LEDGER"
INPUT='{"hook_event_name":"Stop","response":"I will email alice@example.com about the change.","turn":5}'
run_hook "$INPUT" >/dev/null 2>&1
content=$(cat "$LEDGER" 2>/dev/null || echo "")
if echo "$content" | grep -q "alice@example.com"; then
    pii_leaked=yes
else
    pii_leaked=no
fi
assert_eq "4.1 email PII is masked" "no" "$pii_leaked"

# ============================================================
# Group 5: UserPromptSubmit event — task-shift detection
# ============================================================

echo "=== Group 5: UserPromptSubmit — task-shift detection ==="

# Setup: write a known outstanding commitment to ledger
rm -f "$LEDGER"
mkdir -p "$TEST_DIR"
cat > "$LEDGER" << 'EOF'
{"ts":"2026-05-22T23:00:00Z","session_id":"test","turn":1,"commitment_hash":"abc","commitment_summary":"I'll push the changes after tests","byte_length":34,"action_keywords":["push","changes","tests"],"status":"open"}
EOF

# Re-anchor prompt (mentions one of the keywords): advisory should NOT fire
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":"Yes, please push the changes now."}'
out=$(run_hook "$INPUT" 2>&1 >/dev/null)
if echo "$out" | grep -q "ADVISORY"; then
    advisory=yes
else
    advisory=no
fi
assert_eq "5.1 re-anchor prompt: no advisory" "no" "$advisory"

# Task-shift prompt (new sub-task, no re-anchor): advisory should fire (default mode)
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":"Now refactor the database schema for the user table."}'
out=$(run_hook "$INPUT" 2>&1 >/dev/null)
if echo "$out" | grep -q "ADVISORY"; then
    advisory=yes
else
    advisory=no
fi
assert_eq "5.2 task-shift prompt: advisory fires" "yes" "$advisory"

# Pivot marker "instead": advisory should fire
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":"Actually, instead, refactor the user model."}'
out=$(run_hook "$INPUT" 2>&1 >/dev/null)
if echo "$out" | grep -q "ADVISORY"; then
    advisory=yes
else
    advisory=no
fi
assert_eq "5.3 pivot marker: advisory fires" "yes" "$advisory"

# Empty prompt: exit silently
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":""}'
run_hook "$INPUT" >/dev/null 2>&1
assert_eq "5.4 empty prompt exits 0" "0" "$?"

# No ledger file: exit silently
rm -f "$LEDGER"
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":"Anything."}'
run_hook "$INPUT" >/dev/null 2>&1
assert_eq "5.5 no ledger exits 0" "0" "$?"

# ============================================================
# Group 6: Strict mode
# ============================================================

echo "=== Group 6: Strict mode ==="

cat > "$LEDGER" << 'EOF'
{"ts":"2026-05-22T23:00:00Z","session_id":"test","turn":1,"commitment_hash":"abc","commitment_summary":"I'll deploy the staging","byte_length":24,"action_keywords":["deploy","staging"],"status":"open"}
EOF

export CC_COMMITMENT_LEDGER_MODE="strict"

# Strict + pivot + no re-anchor: exit 2
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":"Forget that. Refactor the dashboard now."}'
run_hook "$INPUT" >/dev/null 2>&1
strict_exit=$?
assert_eq "6.1 strict mode + pivot + no re-anchor: exit 2" "2" "$strict_exit"

# Strict + re-anchor: exit 0
INPUT='{"hook_event_name":"UserPromptSubmit","prompt":"Yes, deploy to staging please."}'
run_hook "$INPUT" >/dev/null 2>&1
assert_eq "6.2 strict mode + re-anchor: exit 0" "0" "$?"

unset CC_COMMITMENT_LEDGER_MODE

# ============================================================
# Summary
# ============================================================

echo ""
echo "============================================================"
echo "RESULTS: $PASS passed, $FAIL failed, $((PASS+FAIL)) total"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
