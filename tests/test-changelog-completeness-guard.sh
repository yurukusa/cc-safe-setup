#!/bin/bash
# Tests for changelog-completeness-guard.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/changelog-completeness-guard.sh"
PASS=0
FAIL=0
STATE_DIR="/tmp/cc-changelog-guard"
SESSION_ID="test-$$"
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"
MARK_FILE="$STATE_DIR/${SESSION_ID}.enum-mark"

setup() {
    rm -f "$STATE_DIR"/${SESSION_ID}.* 2>/dev/null || true
    mkdir -p "$STATE_DIR"
}

# run_hook: run hook with input; sets global RC and RUN_OUTPUT
run_hook() {
    local input="$1"
    RUN_OUTPUT=$(printf '%s' "$input" | bash "$HOOK" 2>&1)
    RC=$?
}

run_hook_with_window() {
    local input="$1"
    local window="$2"
    RUN_OUTPUT=$(printf '%s' "$input" | CC_CHANGELOG_GUARD_WINDOW="$window" bash "$HOOK" 2>&1)
    RC=$?
}

# Helper: build a JSON input
mk_input() {
    local tool="$1"
    local extra="$2"
    printf '{"session_id":"%s","tool_name":"%s",%s}' "$SESSION_ID" "$tool" "$extra"
}

assert_pass() {
    local label="$1"
    local rc="$2"
    if [ "$rc" -eq 0 ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (rc=$rc)"
        FAIL=$((FAIL + 1))
    fi
}

assert_block() {
    local label="$1"
    local rc="$2"
    if [ "$rc" -eq 2 ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (rc=$rc, expected 2)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== changelog-completeness-guard.sh tests ==="

# --- Test 1: Write to CHANGELOG.md without prior git log → BLOCK ---
setup
INPUT=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook "$INPUT"
rc=$RC
assert_block "Write to CHANGELOG.md with no enumeration is blocked" "$rc"

# --- Test 2: Write to README.md (not a release-notes file) → ALLOW ---
setup
INPUT=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/README.md","content":"x"}')
run_hook "$INPUT"
rc=$RC
assert_pass "Write to README.md (not release-notes) is allowed" "$rc"

# --- Test 3: Bash with `git log <range>` then Write to CHANGELOG → ALLOW ---
setup
# First call: git log
INPUT1=$(mk_input "Bash" '"tool_input":{"command":"git log v1.0.0..HEAD --oneline"}')
run_hook "$INPUT1"
rc1=$RC
# Second call: Write to CHANGELOG
INPUT2=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook "$INPUT2"
rc2=$RC
assert_pass "Bash git log range then Write to CHANGELOG.md is allowed" "$rc2"

# --- Test 4: Bash with `gh issue list` then Write to CHANGELOG → ALLOW ---
setup
INPUT1=$(mk_input "Bash" '"tool_input":{"command":"gh issue list --state closed --limit 50"}')
run_hook "$INPUT1"
INPUT2=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook "$INPUT2"
rc2=$RC
assert_pass "Bash gh issue list then Write to CHANGELOG.md is allowed" "$rc2"

# --- Test 5: Bash with `gh pr list --state merged` then Write to CHANGELOG → ALLOW ---
setup
INPUT1=$(mk_input "Bash" '"tool_input":{"command":"gh pr list --state merged --search closed:>2026-05-01"}')
run_hook "$INPUT1"
INPUT2=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook "$INPUT2"
rc2=$RC
assert_pass "Bash gh pr list then Write to CHANGELOG.md is allowed" "$rc2"

# --- Test 6: Bash with plain `git log` (no range) does NOT mark → BLOCK on Write ---
setup
INPUT1=$(mk_input "Bash" '"tool_input":{"command":"git log"}')
run_hook "$INPUT1"
INPUT2=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook "$INPUT2"
rc2=$RC
assert_block "Bash git log without range does not mark; Write is blocked" "$rc2"

# --- Test 7: Edit to WIP.md without enumeration → BLOCK ---
setup
INPUT=$(mk_input "Edit" '"tool_input":{"file_path":"/tmp/WIP.md","old_string":"a","new_string":"b"}')
run_hook "$INPUT"
rc=$RC
assert_block "Edit to WIP.md without enumeration is blocked" "$rc"

# --- Test 8: MultiEdit to TODO.md without enumeration → BLOCK ---
setup
INPUT=$(mk_input "MultiEdit" '"tool_input":{"file_path":"/tmp/TODO.md","edits":[]}')
run_hook "$INPUT"
rc=$RC
assert_block "MultiEdit to TODO.md without enumeration is blocked" "$rc"

# --- Test 9: Other tools (Read, Glob, etc.) → ALLOW ---
setup
INPUT=$(mk_input "Read" '"tool_input":{"file_path":"/tmp/CHANGELOG.md"}')
run_hook "$INPUT"
rc=$RC
assert_pass "Read tool is allowed (no write)" "$rc"

# --- Test 10: Block message contains the specific commands to run ---
setup
INPUT=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook "$INPUT"
if echo "$RUN_OUTPUT" | grep -q "git log" && echo "$RUN_OUTPUT" | grep -q "gh issue list"; then
    echo "  PASS: block message names git log and gh issue list"
    PASS=$((PASS + 1))
else
    echo "  FAIL: block message should name remediation commands"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: Mark expires after window of tool calls → BLOCK after expiry ---
setup
# Mark at call 1
INPUT1=$(mk_input "Bash" '"tool_input":{"command":"git log v1..HEAD --oneline"}')
run_hook_with_window "$INPUT1" 3 > /dev/null || true
# Advance counter with unrelated bash calls (3 more calls)
for _ in 1 2 3 4; do
    INPUT_NOOP=$(mk_input "Bash" '"tool_input":{"command":"ls"}')
    run_hook_with_window "$INPUT_NOOP" 3 > /dev/null || true
done
# Now try Write — should be blocked (window=3, age > 3)
INPUT_W=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook_with_window "$INPUT_W" 3
rc=$RC
assert_block "Mark expires after window; Write is re-blocked" "$rc"

# --- Test 12: Override via large window → ALLOW even without enumeration ---
setup
INPUT=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook_with_window "$INPUT" 999999
rc=$RC
# With window=999999, mark=0 still triggers block (0 mark always blocks)
# This documents the actual override behavior: CC_CHANGELOG_GUARD_WINDOW does NOT
# bypass when mark is 0. The hook is conservative by design.
assert_block "Window override alone does not bypass missing-mark block" "$rc"

# --- Test 13: After enumeration + window=999999 → ALLOW even at high count ---
setup
INPUT_E=$(mk_input "Bash" '"tool_input":{"command":"git log v1..HEAD"}')
run_hook_with_window "$INPUT_E" 999999 > /dev/null || true
# Advance counter
for _ in $(seq 1 50); do
    INPUT_NOOP=$(mk_input "Bash" '"tool_input":{"command":"echo"}')
    run_hook_with_window "$INPUT_NOOP" 999999 > /dev/null || true
done
INPUT_W=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/CHANGELOG.md","content":"x"}')
run_hook_with_window "$INPUT_W" 999999
rc=$RC
assert_pass "Enumeration + large window survives 50 unrelated calls" "$rc"

# --- Test 14: RELEASES.md is also guarded ---
setup
INPUT=$(mk_input "Write" '"tool_input":{"file_path":"/tmp/RELEASES.md","content":"x"}')
run_hook "$INPUT"
rc=$RC
assert_block "Write to RELEASES.md without enumeration is blocked" "$rc"

# --- Test 15: Path with directory prefix still matches by basename ---
setup
INPUT=$(mk_input "Write" '"tool_input":{"file_path":"/home/user/repo/docs/CHANGELOG.md","content":"x"}')
run_hook "$INPUT"
rc=$RC
assert_block "Write to docs/CHANGELOG.md (nested path) is blocked" "$rc"

# Cleanup
rm -f "$STATE_DIR"/${SESSION_ID}.* 2>/dev/null || true

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
