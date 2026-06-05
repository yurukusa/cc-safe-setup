#!/bin/bash
# Tests for multi-file-plan-routing-gate.sh
#
# Verifies the PreToolUse hook behavior for #60506 recommendation 7:
#   - First two file writes pass silently
#   - Third+ file write without plan file → blocks
#   - Plan file present → all writes pass silently
#   - Same file written twice does not increment counter (deduplication)
#   - Custom threshold respected
#   - Disable flag respected
#   - Empty input → silent
#   - Missing file_path → silent
#   - Stale state TTL cleanup (older than N days removed)

set -uo pipefail

HOOK="$(dirname "$0")/../examples/multi-file-plan-routing-gate.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Use unique state dir per test run to avoid cross-contamination
TEST_STATE_DIR=$(mktemp -d)
export CC_PLAN_GATE_ENABLE=1   # gate is opt-in; enable it for the block-mode tests
TEST_PLAN_DIR=$(mktemp -d)
SESSION="test-session-$$"

run_hook() {
    local input="$1"
    local extra_env="${2:-}"
    if [ -n "$extra_env" ]; then
        eval "CC_PLAN_GATE_STATE_DIR='$TEST_STATE_DIR' CC_PLAN_GATE_PLAN_DIR='$TEST_PLAN_DIR' $extra_env bash '$HOOK'" <<< "$input" 2>&1
    else
        CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" \
            printf '%s' "$input" | bash "$HOOK" 2>&1
    fi
}

cleanup() {
    rm -rf "$TEST_STATE_DIR" "$TEST_PLAN_DIR" 2>/dev/null || true
}
trap cleanup EXIT

mk_input() {
    local sess="$1"
    local path="$2"
    jq -nc --arg s "$sess" --arg p "$path" '{
        session_id: $s,
        tool_input: {file_path: $p}
    }'
}

echo "=== multi-file-plan-routing-gate.sh tests ==="

# --- Test 1: first file → silent ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
INPUT=$(mk_input "$SESSION-1" "/tmp/a.md")
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "first file is silent"
else
    assert_fail "expected silent, got rc=$rc out=$out"
fi

# --- Test 2: second file → silent ---
INPUT=$(mk_input "$SESSION-1" "/tmp/b.md")
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "second file is silent"
else
    assert_fail "expected silent, got rc=$rc out=$out"
fi

# --- Test 3: third file without plan → blocks ---
INPUT=$(mk_input "$SESSION-1" "/tmp/c.md")
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "MULTI-FILE CHANGE WITHOUT A PLAN"; then
    assert_pass "third file without plan blocks (exit 2)"
else
    assert_fail "expected exit 2 + feedback, got rc=$rc out=$out"
fi

# --- Test 4: plan file present → third file passes ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
SESSION_2="$SESSION-2"
SAFE_2=$(printf '%s' "$SESSION_2" | tr -c '[:alnum:]_-' '_' | head -c 64)
echo "Plan: ..." > "$TEST_PLAN_DIR/${SAFE_2}.md"

# Touch 3 files
for f in /tmp/x.md /tmp/y.md /tmp/z.md; do
    INPUT=$(mk_input "$SESSION_2" "$f")
    out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then break; fi
done
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "plan file present allows multi-file writes"
else
    assert_fail "plan present should allow, got rc=$rc out=$out"
fi

# --- Test 5: same file twice does not double-count (dedup) ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
SESSION_3="$SESSION-3"
# Touch same file twice and one different file
INPUT=$(mk_input "$SESSION_3" "/tmp/same.md")
CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" >/dev/null 2>&1
CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" >/dev/null 2>&1
INPUT=$(mk_input "$SESSION_3" "/tmp/different.md")
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "same file twice does not count twice (dedup)"
else
    assert_fail "dedup failed, got rc=$rc"
fi

# --- Test 6: custom threshold (5) respected ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
SESSION_4="$SESSION-4"
# Touch 4 files - should pass under threshold=5
for f in /tmp/p1.md /tmp/p2.md /tmp/p3.md /tmp/p4.md; do
    INPUT=$(mk_input "$SESSION_4" "$f")
    out=$(CC_PLAN_GATE_THRESHOLD=5 CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then break; fi
done
if [ "$rc" -eq 0 ]; then
    assert_pass "threshold=5 allows 4 files"
else
    assert_fail "threshold=5 should allow 4, got rc=$rc"
fi

# Now touch 5th file - should block
INPUT=$(mk_input "$SESSION_4" "/tmp/p5.md")
out=$(CC_PLAN_GATE_THRESHOLD=5 CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "threshold=5 blocks 5th file"
else
    assert_fail "threshold=5 should block 5th, got rc=$rc"
fi

# --- Test 7: disable flag silences hook entirely ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
SESSION_5="$SESSION-5"
for f in /tmp/q1.md /tmp/q2.md /tmp/q3.md /tmp/q4.md; do
    INPUT=$(mk_input "$SESSION_5" "$f")
    out=$(CC_PLAN_GATE_DISABLE=1 CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ] || [ -n "$out" ]; then break; fi
done
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "CC_PLAN_GATE_DISABLE=1 silences hook"
else
    assert_fail "disable flag failed, got rc=$rc"
fi

# --- Test 8: empty input → silent ---
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "empty input is silent"
else
    assert_fail "empty should be silent, got rc=$rc"
fi

# --- Test 9: missing file_path → silent ---
INPUT=$(jq -nc --arg s "$SESSION-6" '{session_id: $s, tool_input: {}}')
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "missing file_path is silent"
else
    assert_fail "missing path should be silent, got rc=$rc"
fi

# --- Test 10: generic plan.md acts as escape hatch ---
rm -rf "$TEST_STATE_DIR"/* "$TEST_PLAN_DIR"/* 2>/dev/null
SESSION_7="$SESSION-7"
echo "Generic plan" > "$TEST_PLAN_DIR/plan.md"
for f in /tmp/r1.md /tmp/r2.md /tmp/r3.md; do
    INPUT=$(mk_input "$SESSION_7" "$f")
    out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then break; fi
done
if [ "$rc" -eq 0 ]; then
    assert_pass "generic plan.md acts as escape hatch"
else
    assert_fail "generic plan.md should allow, got rc=$rc"
fi

# --- Test 11: block message lists files touched so far ---
rm -rf "$TEST_STATE_DIR"/* "$TEST_PLAN_DIR"/* 2>/dev/null
SESSION_8="$SESSION-8"
for f in /tmp/listed-a.md /tmp/listed-b.md; do
    INPUT=$(mk_input "$SESSION_8" "$f")
    CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" >/dev/null 2>&1
done
INPUT=$(mk_input "$SESSION_8" "/tmp/listed-c.md")
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
if echo "$out" | grep -q "listed-a.md" && echo "$out" | grep -q "listed-b.md"; then
    assert_pass "block message lists files touched so far"
else
    assert_fail "block message should list files, got: $out"
fi

# --- Test 12: state file persists between invocations within session ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
SESSION_9="$SESSION-9"
INPUT=$(mk_input "$SESSION_9" "/tmp/persist-a.md")
CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" >/dev/null 2>&1
SAFE_9=$(printf '%s' "$SESSION_9" | tr -c '[:alnum:]_-' '_' | head -c 64)
if [ -f "$TEST_STATE_DIR/${SAFE_9}.files" ] && grep -q "persist-a.md" "$TEST_STATE_DIR/${SAFE_9}.files"; then
    assert_pass "state file persists with file_path recorded"
else
    assert_fail "state file missing or empty"
fi

# --- Test 13: different sessions tracked independently ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
# Session A touches 2 files (under threshold)
for f in /tmp/iso-a1.md /tmp/iso-a2.md; do
    INPUT=$(mk_input "iso-A" "$f")
    CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" >/dev/null 2>&1
done
# Session B touches its first file - should still be silent (independent counter)
INPUT=$(mk_input "iso-B" "/tmp/iso-b1.md")
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "sessions tracked independently"
else
    assert_fail "session isolation broken, got rc=$rc"
fi

# --- Test 14: session_id default when missing ---
rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
INPUT=$(jq -nc '{tool_input: {file_path: "/tmp/no-session.md"}}')
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$TEST_STATE_DIR/default.files" ]; then
    assert_pass "missing session_id falls back to default"
else
    assert_fail "default session fallback broken, got rc=$rc"
fi

# --- Test 15: malformed JSON input → no crash ---
out=$(CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" printf 'not json' | bash "$HOOK" 2>&1)
rc=$?
if ! echo "$out" | grep -qi "error\|traceback\|syntax"; then
    assert_pass "malformed input does not crash"
else
    assert_fail "malformed input crashed, got: $out"
fi

rm -rf "$TEST_STATE_DIR"/* 2>/dev/null
for f in /tmp/x1.md /tmp/x2.md /tmp/x3.md; do
    INPUT=$(mk_input "$SESSION-optin" "$f")
    out=$(env -u CC_PLAN_GATE_ENABLE CC_PLAN_GATE_STATE_DIR="$TEST_STATE_DIR" CC_PLAN_GATE_PLAN_DIR="$TEST_PLAN_DIR" bash "$HOOK" <<< "$INPUT" 2>&1)
    rc=$?
done
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    assert_pass "gate is off by default (CC_PLAN_GATE_ENABLE unset → 3rd file silent)"
else
    assert_fail "expected silent no-op without CC_PLAN_GATE_ENABLE, got rc=$rc out=$out"
fi
echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
