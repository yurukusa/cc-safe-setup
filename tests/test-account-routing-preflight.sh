#!/bin/bash
# Tests for account-routing-preflight.sh
HOOK="examples/account-routing-preflight.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Hook root resolves relative to repo root
HOOK_ABS="$PWD/$HOOK"

# Test 1: No .claude/expected-account in cwd → silent pass
mkdir -p "$TMPDIR/project1"
OUT=$(cd "$TMPDIR/project1" && bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no expected-account no warning" "$OUT" "mismatch"
assert_exit "no expected-account exit 0" "$RC" "0"

# Test 2: Empty expected-account file → silent pass
mkdir -p "$TMPDIR/project2/.claude"
touch "$TMPDIR/project2/.claude/expected-account"
OUT=$(cd "$TMPDIR/project2" && bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "empty expected-account no warning" "$OUT" "mismatch"
assert_exit "empty expected-account exit 0" "$RC" "0"

# Test 3: Match (active == expected) → silent pass
mkdir -p "$TMPDIR/project3/.claude"
echo "work" > "$TMPDIR/project3/.claude/expected-account"
OUT=$(cd "$TMPDIR/project3" && ANTHROPIC_ACCOUNT_LABEL=work bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "match no warning" "$OUT" "mismatch"
assert_exit "match exit 0" "$RC" "0"

# Test 4: Mismatch (active != expected) → refuse with exit 2
mkdir -p "$TMPDIR/project4/.claude"
echo "client-a" > "$TMPDIR/project4/.claude/expected-account"
OUT=$(cd "$TMPDIR/project4" && ANTHROPIC_ACCOUNT_LABEL=personal bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "mismatch warns" "$OUT" "mismatch"
assert_contains "mismatch shows expected" "$OUT" "client-a"
assert_contains "mismatch shows active" "$OUT" "personal"
assert_exit "mismatch exit 2" "$RC" "2"

# Test 5: Mismatch with unset label (defaults to "unknown")
mkdir -p "$TMPDIR/project5/.claude"
echo "client-b" > "$TMPDIR/project5/.claude/expected-account"
OUT=$(cd "$TMPDIR/project5" && unset ANTHROPIC_ACCOUNT_LABEL && bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "unset label warns" "$OUT" "mismatch"
assert_contains "unset label shows unknown" "$OUT" "unknown"
assert_exit "unset label exit 2" "$RC" "2"

# Test 6: Whitespace in expected-account file is stripped
mkdir -p "$TMPDIR/project6/.claude"
printf "  work  \n" > "$TMPDIR/project6/.claude/expected-account"
OUT=$(cd "$TMPDIR/project6" && ANTHROPIC_ACCOUNT_LABEL=work bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "whitespace stripped no warning" "$OUT" "mismatch"
assert_exit "whitespace stripped exit 0" "$RC" "0"

# Test 7: Disable env var skips the gate even on mismatch
mkdir -p "$TMPDIR/project7/.claude"
echo "client-c" > "$TMPDIR/project7/.claude/expected-account"
OUT=$(cd "$TMPDIR/project7" && \
    ANTHROPIC_ACCOUNT_LABEL=personal \
    CC_ACCOUNT_PREFLIGHT_DISABLE=1 \
    bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable skips gate" "$OUT" "mismatch"
assert_exit "disable exit 0 despite mismatch" "$RC" "0"

# Test 8: Mismatch message includes the fix suggestion
mkdir -p "$TMPDIR/project8/.claude"
echo "client-d" > "$TMPDIR/project8/.claude/expected-account"
OUT=$(cd "$TMPDIR/project8" && ANTHROPIC_ACCOUNT_LABEL=personal bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "fix suggests switch" "$OUT" "cc-client-d"
assert_contains "fix suggests verify" "$OUT" "ANTHROPIC_ACCOUNT_LABEL"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
