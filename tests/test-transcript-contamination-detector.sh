#!/bin/bash
# Tests for transcript-contamination-detector.sh
#
# Verifies the SessionStart hook behavior for issue #60802:
#   - Clean .jsonl files → silent exit 0
#   - .jsonl with both synthetic markers → exit 0 + stderr warning
#   - .jsonl with only one marker (incomplete) → no detection
#   - Missing projects dir → silent exit 0
#   - Disable flag respected
#   - Multiple contaminated files → all reported, with truncation if >5

set -uo pipefail

HOOK="$(dirname "$0")/../examples/transcript-contamination-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Set up a sandbox projects directory
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT
export CC_PROJECTS_DIR="$TEST_DIR/.claude/projects"
mkdir -p "$CC_PROJECTS_DIR/-home-user-myproject"

USER_MARKER='{"isMeta": true, "content": "Continue from where you left off.", "type": "user"}'
ASSISTANT_MARKER='{"model": "<synthetic>", "content": "No response requested.", "type": "assistant"}'
CLEAN_USER='{"role": "user", "content": "Hello"}'
CLEAN_ASSISTANT='{"role": "assistant", "content": "Hi"}'

run_hook() {
    bash "$HOOK" 2>&1 < /dev/null
}

echo "=== transcript-contamination-detector.sh tests ==="

# --- Test 1: Clean .jsonl → silent ---
SESSION1="$CC_PROJECTS_DIR/-home-user-myproject/clean-session.jsonl"
printf '%s\n%s\n' "$CLEAN_USER" "$CLEAN_ASSISTANT" > "$SESSION1"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "clean .jsonl → silent exit 0"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 2: .jsonl with both synthetic markers → warning ---
SESSION2="$CC_PROJECTS_DIR/-home-user-myproject/contaminated.jsonl"
printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$SESSION2"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "TRANSCRIPT CONTAMINATION DETECTED"; then
    assert_pass "contaminated .jsonl → exit 0 + warning"
else
    assert_fail "expected warning, got rc=$rc output=$output"
fi

# --- Test 3: .jsonl with only user marker (no assistant) → no detection ---
rm "$SESSION2"
SESSION3="$CC_PROJECTS_DIR/-home-user-myproject/partial.jsonl"
printf '%s\n%s\n' "$USER_MARKER" "$CLEAN_ASSISTANT" > "$SESSION3"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "partial markers → no false positive"
else
    assert_fail "expected silent on partial markers, got rc=$rc output=$output"
fi

# --- Test 4: .jsonl with only assistant marker → no detection ---
rm "$SESSION3"
SESSION4="$CC_PROJECTS_DIR/-home-user-myproject/partial2.jsonl"
printf '%s\n%s\n' "$CLEAN_USER" "$ASSISTANT_MARKER" > "$SESSION4"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "partial markers (assistant only) → no false positive"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 5: Missing projects directory → silent ---
rm "$SESSION4"
rm -rf "$CC_PROJECTS_DIR"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing projects dir → silent exit 0"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi
mkdir -p "$CC_PROJECTS_DIR/-home-user-myproject"

# --- Test 6: Disable flag respected ---
SESSION6="$CC_PROJECTS_DIR/-home-user-myproject/contaminated.jsonl"
printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$SESSION6"
output=$(CC_TRANSCRIPT_DETECTOR_DISABLE=1 bash "$HOOK" 2>&1 < /dev/null)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag → silent exit 0 even with contamination"
else
    assert_fail "expected disabled, got rc=$rc output=$output"
fi

# --- Test 7: Multiple contaminated files ---
for i in 1 2 3; do
    f="$CC_PROJECTS_DIR/-home-user-myproject/contaminated-$i.jsonl"
    printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$f"
done
output=$(run_hook)
rc=$?
count=$(echo "$output" | grep -c "/contaminated.*\.jsonl")
if [ "$rc" -eq 0 ] && [ "$count" -ge 3 ]; then
    assert_pass "multiple contaminated files → all listed (found $count)"
else
    assert_fail "expected 3+ paths listed, got count=$count output=$output"
fi

# --- Test 8: Markers on same line (variant) ---
rm "$CC_PROJECTS_DIR/-home-user-myproject/"*.jsonl
SESSION8="$CC_PROJECTS_DIR/-home-user-myproject/same-line.jsonl"
# Both markers in a single line — still should detect
echo "$USER_MARKER $ASSISTANT_MARKER" > "$SESSION8"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "TRANSCRIPT CONTAMINATION DETECTED"; then
    assert_pass "markers on same line → detected"
else
    assert_fail "expected detection, got rc=$rc output=$output"
fi

# --- Test 9: Whitespace variations in markers ---
rm "$SESSION8"
SESSION9="$CC_PROJECTS_DIR/-home-user-myproject/whitespace.jsonl"
# Test that "isMeta":true (no space) still matches
USER_NOSPACE='{"isMeta":true,"content":"Continue from where you left off.","type":"user"}'
ASSISTANT_NOSPACE='{"model":"<synthetic>","content":"No response requested.","type":"assistant"}'
printf '%s\n%s\n' "$USER_NOSPACE" "$ASSISTANT_NOSPACE" > "$SESSION9"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "TRANSCRIPT CONTAMINATION DETECTED"; then
    assert_pass "no-whitespace JSON variant → detected"
else
    assert_fail "expected detection, got rc=$rc output=$output"
fi

# --- Test 10: Markers inside a long-running session (mixed real + synthetic) ---
rm "$SESSION9"
SESSION10="$CC_PROJECTS_DIR/-home-user-myproject/long-mixed.jsonl"
{
    echo "$CLEAN_USER"
    echo "$CLEAN_ASSISTANT"
    echo "$CLEAN_USER"
    echo "$CLEAN_ASSISTANT"
    echo "$USER_MARKER"
    echo "$ASSISTANT_MARKER"
    echo "$CLEAN_USER"
    echo "$CLEAN_ASSISTANT"
} > "$SESSION10"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "long-mixed.jsonl"; then
    assert_pass "mixed real + synthetic content → detected"
else
    assert_fail "expected detection, got rc=$rc output=$output"
fi

# --- Test 11: Hook runs without error when no .jsonl exists ---
rm "$SESSION10"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no .jsonl files → silent exit 0"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 12: Hook handles files with no projects/<encoded-path> nesting ---
SESSION12="$CC_PROJECTS_DIR/loose.jsonl"
printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$SESSION12"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "loose.jsonl"; then
    assert_pass "files in projects root (no nested dir) → detected"
else
    assert_fail "expected detection, got rc=$rc output=$output"
fi

# --- Test 13: MAX_FILES cap works ---
rm "$SESSION12"
for i in $(seq 1 5); do
    f="$CC_PROJECTS_DIR/-home-user-myproject/session-cap-$i.jsonl"
    printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$f"
done
output=$(CC_TRANSCRIPT_DETECTOR_MAX=2 bash "$HOOK" 2>&1 < /dev/null)
rc=$?
count=$(echo "$output" | grep -c "session-cap.*\.jsonl")
if [ "$rc" -eq 0 ] && [ "$count" -le 2 ]; then
    assert_pass "MAX_FILES cap of 2 → at most 2 scanned (got $count)"
else
    assert_fail "expected ≤2, got count=$count output=$output"
fi

# --- Test 14: Truncation when >5 files ---
rm "$CC_PROJECTS_DIR/-home-user-myproject/"*.jsonl
for i in $(seq 1 7); do
    f="$CC_PROJECTS_DIR/-home-user-myproject/many-$i.jsonl"
    printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$f"
done
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "and 2 more"; then
    assert_pass "truncates output when >5 files (says 'and 2 more')"
else
    assert_fail "expected truncation message, got output=$output"
fi

# --- Test 15: Header message format ---
rm "$CC_PROJECTS_DIR/-home-user-myproject/"*.jsonl
SESSION15="$CC_PROJECTS_DIR/-home-user-myproject/single.jsonl"
printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$SESSION15"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "anthropics/claude-code#60802"; then
    assert_pass "warning references issue #60802"
else
    assert_fail "missing issue reference, got output=$output"
fi

# --- Test 16: Empty .jsonl file → no detection ---
rm "$SESSION15"
SESSION16="$CC_PROJECTS_DIR/-home-user-myproject/empty.jsonl"
: > "$SESSION16"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty .jsonl → silent"
else
    assert_fail "expected silent on empty, got rc=$rc output=$output"
fi

# --- Test 17: Recommendations included in warning ---
rm "$SESSION16"
SESSION17="$CC_PROJECTS_DIR/-home-user-myproject/with-recs.jsonl"
printf '%s\n%s\n' "$USER_MARKER" "$ASSISTANT_MARKER" > "$SESSION17"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "restore the affected file from backup"; then
    assert_pass "warning includes restore-from-backup recommendation"
else
    assert_fail "missing recommendation, got output=$output"
fi

if [ "$rc" -eq 0 ] && echo "$output" | grep -q "open the desired session"; then
    assert_pass "warning includes workaround"
else
    assert_fail "missing workaround, got output=$output"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
