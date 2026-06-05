#!/bin/bash
# Tests for memory-orphan-detector.sh
#
# Verifies the SessionStart hook behavior for issue #61349:
#   - Current memory has content → silent exit 0
#   - Current memory empty + no git history → silent
#   - Current memory empty + git history + no orphan candidates → silent
#   - Current memory empty + git history + orphan candidates → warning
#   - Disable flag respected
#   - Multiple orphan candidates → top 5 listed
#   - Threshold environment variables respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/memory-orphan-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Set up a sandbox
TEST_ROOT=$(mktemp -d)
trap "rm -rf $TEST_ROOT" EXIT
export CC_PROJECTS_DIR="$TEST_ROOT/projects"
mkdir -p "$CC_PROJECTS_DIR"

# Create a project working directory with git history
PROJECT_DIR="$TEST_ROOT/myproject"
mkdir -p "$PROJECT_DIR"
git -C "$PROJECT_DIR" init --quiet
git -C "$PROJECT_DIR" config user.email "test@example.com"
git -C "$PROJECT_DIR" config user.name "Test"
for i in 1 2 3 4 5 6 7 8; do
    echo "content $i" > "$PROJECT_DIR/file$i.txt"
    git -C "$PROJECT_DIR" add "file$i.txt"
    git -C "$PROJECT_DIR" commit --quiet -m "Commit $i"
done

# Encode helper for the project path
encode() { printf '%s' "$1" | tr '/.' '--'; }
PROJECT_ENCODED=$(encode "$PROJECT_DIR")
PROJECT_MEMORY="$CC_PROJECTS_DIR/$PROJECT_ENCODED/memory"

run_hook() {
    (cd "$PROJECT_DIR" && bash "$HOOK") 2>&1
}

echo "=== memory-orphan-detector.sh tests ==="

# --- Test 1: current memory has content → silent ---
mkdir -p "$PROJECT_MEMORY"
for i in 1 2 3; do
    echo "memory entry $i" > "$PROJECT_MEMORY/entry$i.md"
done
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "current memory has content → silent exit 0"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 2: current memory empty + no git history → silent ---
rm -rf "$PROJECT_MEMORY"
mkdir -p "$PROJECT_MEMORY"
NO_GIT_DIR="$TEST_ROOT/no-git"
mkdir -p "$NO_GIT_DIR"
NO_GIT_ENCODED=$(encode "$NO_GIT_DIR")
mkdir -p "$CC_PROJECTS_DIR/$NO_GIT_ENCODED/memory"
output=$(cd "$NO_GIT_DIR" && bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty memory + no git history → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 3: current memory empty + git history + no orphan candidates → silent ---
rm -rf "$CC_PROJECTS_DIR"
mkdir -p "$PROJECT_MEMORY"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty + git history + no orphans → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 4: empty + git history + ONE orphan candidate (substantive) → warning ---
ORPHAN1="$CC_PROJECTS_DIR/-tmp-someoldpath/memory"
mkdir -p "$ORPHAN1"
for i in 1 2 3 4 5 6; do
    # Each entry > 400 bytes so total > 2048
    printf 'entry %d %s\n' "$i" "$(printf 'x%.0s' $(seq 1 400))" > "$ORPHAN1/entry$i.md"
done
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "POSSIBLE MEMORY ORPHANING DETECTED"; then
    assert_pass "candidate orphan present → warning"
else
    assert_fail "expected warning, got rc=$rc output=$output"
fi

# --- Test 5: warning references issue #61349 ---
if echo "$output" | grep -q "claude-code#61349"; then
    assert_pass "warning references issue #61349"
else
    assert_fail "missing issue ref, got $output"
fi

# --- Test 6: warning lists candidate orphan path ---
if echo "$output" | grep -q "tmp-someoldpath"; then
    assert_pass "candidate orphan path listed"
else
    assert_fail "missing candidate path"
fi

# --- Test 7: disable flag respected ---
output=$(CC_MEMORY_ORPHAN_DISABLE=1 bash -c "cd '$PROJECT_DIR' && bash '$HOOK'" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag → silent even when conditions match"
else
    assert_fail "expected disabled, got rc=$rc output=$output"
fi

# --- Test 8: missing projects dir → silent ---
rm -rf "$CC_PROJECTS_DIR"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing projects dir → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi
mkdir -p "$PROJECT_MEMORY"

# --- Test 9: orphan below entry threshold → not flagged ---
ORPHAN_SMALL="$CC_PROJECTS_DIR/-tmp-small/memory"
mkdir -p "$ORPHAN_SMALL"
echo "single tiny file" > "$ORPHAN_SMALL/e1.md"  # below ORPHAN_THRESHOLD (5) entries
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "below threshold orphan → not flagged"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 10: orphan below byte threshold → not flagged ---
ORPHAN_TINY="$CC_PROJECTS_DIR/-tmp-tiny/memory"
mkdir -p "$ORPHAN_TINY"
for i in 1 2 3 4 5 6; do echo "x" > "$ORPHAN_TINY/e$i.md"; done  # 5 entries but tiny bytes
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "tiny-byte orphan → not flagged"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 11: configurable thresholds ---
output=$(CC_MEMORY_ORPHAN_THRESHOLD=3 CC_MEMORY_ORPHAN_MIN_BYTES=8 \
    bash -c "cd '$PROJECT_DIR' && bash '$HOOK'" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "POSSIBLE MEMORY ORPHANING"; then
    assert_pass "lowered thresholds → orphans now flagged"
else
    assert_fail "expected detection with relaxed thresholds, got rc=$rc output=$output"
fi

# --- Test 12: multiple orphans → top 5 listed ---
# Clean and recreate
rm -rf "$CC_PROJECTS_DIR"
mkdir -p "$PROJECT_MEMORY"
for n in 1 2 3 4 5 6 7; do
    o="$CC_PROJECTS_DIR/-tmp-orphan$n/memory"
    mkdir -p "$o"
    for i in 1 2 3 4 5 6; do
        printf 'orphan %d entry %d %s\n' "$n" "$i" "$(printf 'x%.0s' $(seq 1 400))" > "$o/e$i.md"
    done
done
output=$(run_hook)
rc=$?
listed=$(echo "$output" | grep -c "tmp-orphan")
if [ "$rc" -eq 0 ] && [ "$listed" -ge 5 ] && [ "$listed" -le 6 ]; then
    assert_pass "multiple orphans → 5 listed (got $listed)"
else
    assert_fail "expected ~5 listed, got listed=$listed output=$output"
fi

# --- Test 13: truncation message for >5 orphans ---
if echo "$output" | grep -q "and 2 more"; then
    assert_pass "truncation message appears (and 2 more)"
else
    assert_fail "expected 'and 2 more', got $output"
fi

# --- Test 14: recommendation includes manual migration ---
if echo "$output" | grep -q "cp -r"; then
    assert_pass "recommendation includes cp -r migration command"
else
    assert_fail "missing migration recommendation"
fi

# --- Test 15: encoded form printed ---
ENCODED_EXPECTED="$PROJECT_ENCODED"
if echo "$output" | grep -qF -- "$ENCODED_EXPECTED"; then
    assert_pass "current encoded form printed in warning"
else
    assert_fail "missing encoded form, expected $ENCODED_EXPECTED"
fi

# --- Test 16: hook exits 0 (does not block session) ---
if [ "$rc" -eq 0 ]; then
    assert_pass "hook exits 0 (non-blocking)"
else
    assert_fail "hook returned non-zero rc=$rc"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
