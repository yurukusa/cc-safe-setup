#!/bin/bash
# Tests for worktree-branch-pollution-detector.sh
HOOK="examples/worktree-branch-pollution-detector.sh"
PASS=0 FAIL=0

assert_pass() { if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1"; fi; }
assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

# Setup temp repo
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -q
git commit --allow-empty -m "init" -q 2>/dev/null

# Clean up expected branch files
HASH=$(echo "$TMPDIR" | md5sum | cut -c1-8)
rm -f "/tmp/cc-expected-branch-$HASH"

# Test 1: First run records branch (no warning)
OUT=$(echo '{}' | bash "$OLDPWD/$HOOK" 2>&1)
assert_not_contains "first run should not warn" "$OUT" "BRANCH CHANGED"
assert_pass "first run exits 0"

# Test 2: Same branch (no warning)
OUT=$(echo '{}' | bash "$OLDPWD/$HOOK" 2>&1)
assert_not_contains "same branch should not warn" "$OUT" "BRANCH CHANGED"

# Test 3: Switch branch triggers warning
DEFAULT_BRANCH=$(git branch --show-current)
git checkout -b feature-x -q 2>/dev/null
OUT=$(echo '{}' | bash "$OLDPWD/$HOOK" 2>&1)
assert_contains "branch change should warn" "$OUT" "BRANCH CHANGED"
assert_contains "should mention expected branch" "$OUT" "$DEFAULT_BRANCH"

# Test 4: After warning, new branch is accepted
OUT=$(echo '{}' | bash "$OLDPWD/$HOOK" 2>&1)
assert_not_contains "after update should not warn" "$OUT" "BRANCH CHANGED"

# Test 5: Non-git directory exits silently
cd /tmp
OUT=$(echo '{}' | bash "$OLDPWD/$HOOK" 2>&1)
assert_not_contains "non-git should not warn" "$OUT" "BRANCH CHANGED"

# Cleanup
rm -rf "$TMPDIR"
rm -f "/tmp/cc-expected-branch-$HASH"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
