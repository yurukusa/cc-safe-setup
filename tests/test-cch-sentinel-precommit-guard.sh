#!/bin/bash
# Tests for cch-sentinel-precommit-guard.sh
# This guard depends on `git diff --cached`, so we stage/unstage real files in
# a throw-away repo.
set -u
HOOK_ABS="$(pwd)/examples/cch-sentinel-precommit-guard.sh"
PASS=0 FAIL=0

assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }
assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }

TMPREPO=$(mktemp -d)
trap 'rm -rf "$TMPREPO"' EXIT
cd "$TMPREPO" || exit 1
git init -q
git config user.email "t@t.test"
git config user.name "t"
git commit --allow-empty -m init -q

# Test 1: Clean staged diff passes
echo "clean text" > file1.txt
git add file1.txt
OUT=$(bash "$HOOK_ABS" 2>&1)
RC=$?
assert_exit "clean diff exits 0" "$RC" 0

# Test 2: Sentinel in staged diff blocks commit
git reset -q
echo "some code with cch=00000 inside it" > bad.txt
git add bad.txt
OUT=$(bash "$HOOK_ABS" 2>&1)
RC=$?
assert_exit "sentinel blocks commit" "$RC" 1
assert_contains "warning names the string" "$OUT" "cch=00000"
assert_contains "warning references Incident 3" "$OUT" "Incident 3"

# Test 3: Sentinel in allowed docs path passes
git reset -q
mkdir -p docs
echo "docs: the sentinel literal is cch=00000" > docs/incident3.md
git add docs/incident3.md
OUT=$(CCH_ALLOW_PATHS="docs/" bash "$HOOK_ABS" 2>&1)
RC=$?
assert_exit "allowed path passes" "$RC" 0

# Test 4: Sentinel in non-allowed path still blocks even with allowlist set
git reset -q
echo "cch=00000" > src.sh
git add src.sh
OUT=$(CCH_ALLOW_PATHS="docs/" bash "$HOOK_ABS" 2>&1)
RC=$?
assert_exit "non-allowlisted sentinel blocks" "$RC" 1

# Test 5: Partial match of sentinel (e.g. cch=00000abc) — spec says literal
# substring, so this should still block (substring match is the bug surface).
git reset -q
echo "prefix cch=000001 suffix" > partial.txt
git add partial.txt
OUT=$(bash "$HOOK_ABS" 2>&1)
RC=$?
assert_exit "substring match blocks" "$RC" 1

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
