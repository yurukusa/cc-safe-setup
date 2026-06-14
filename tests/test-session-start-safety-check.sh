#!/bin/bash
# Tests for session-start-safety-check.sh — verifies the SessionStart hook
# surfaces uncommitted/unpushed/stashed state, and in particular distinguishes
# crash/teleport "auto-stash" entries (which hide uncommitted work behind a
# clean working tree, #66060) from ordinary manual stashes.

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/session-start-safety-check.sh"
TMPROOT=$(mktemp -d)
trap "rm -rf $TMPROOT 2>/dev/null" EXIT

PASS=0
FAIL=0
assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Build an isolated git repo with one committed file, return its path.
make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        git init -q
        git config user.email t@t.t
        git config user.name t
        git config commit.gpgsign false
        echo base > base.txt
        git add base.txt
        git commit -qm init
    )
}

echo "=== session-start-safety-check.sh tests ==="

# --- Test 1: Not a git repo → silent exit 0 ---
mkdir -p "$TMPROOT/nogit"
output=$( cd "$TMPROOT/nogit" && bash "$HOOK" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-git dir → silent exit 0"
else
    assert_fail "expected silent, got rc=$rc output=[$output]"
fi

# --- Test 2: Clean repo → all-clear, no warnings ---
make_repo "$TMPROOT/clean"
output=$( cd "$TMPROOT/clean" && bash "$HOOK" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$output" | grep -q "Working tree clean"; then
    assert_pass "clean repo → all-clear line"
else
    assert_fail "expected all-clear, got rc=$rc output=[$output]"
fi

# --- Test 3: Crash auto-stash entry → strong warning + recovery guidance ---
make_repo "$TMPROOT/autostash"
(
    cd "$TMPROOT/autostash" || exit 1
    echo work-in-progress >> base.txt
    # Mimic the SDK teardown message template.
    git stash push -q -m "auto-stash: agent supervisor (sess-abc) crashed at 2026-06-07T14:24:31Z"
)
output=$( cd "$TMPROOT/autostash" && bash "$HOOK" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$output" | grep -q "harness auto-stashes" \
   && printf '%s' "$output" | grep -q "stash apply" \
   && printf '%s' "$output" | grep -q "66060"; then
    assert_pass "auto-stash → surfaced with recovery guidance"
else
    assert_fail "expected auto-stash warning, got rc=$rc output=[$output]"
fi

# --- Test 4: auto-stash present → does NOT falsely claim all-clear ---
if printf '%s' "$output" | grep -q "Working tree clean"; then
    assert_fail "auto-stash present but hook still said 'Working tree clean'"
else
    assert_pass "auto-stash suppresses the misleading all-clear line"
fi

# --- Test 5: Ordinary manual stash → generic note, NOT the auto-stash warning ---
make_repo "$TMPROOT/manual"
(
    cd "$TMPROOT/manual" || exit 1
    echo tweak >> base.txt
    git stash push -q -m "trying something"   # default-style manual stash
)
output=$( cd "$TMPROOT/manual" && bash "$HOOK" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$output" | grep -q "stashed changes exist" \
   && ! printf '%s' "$output" | grep -q "crash/teleport auto-stashes"; then
    assert_pass "manual stash → generic note, no false auto-stash warning"
else
    assert_fail "expected generic stash note, got rc=$rc output=[$output]"
fi

# --- Test 6: Hook never blocks (always exit 0) even with everything dirty ---
make_repo "$TMPROOT/dirty"
(
    cd "$TMPROOT/dirty" || exit 1
    echo uncommitted >> base.txt
    echo extra >> base.txt
    git add extra >/dev/null 2>&1 || true
)
( cd "$TMPROOT/dirty" && bash "$HOOK" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "dirty tree → still exit 0 (advisory, never blocks)"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test: jq missing → loud fail-open warning, still exit 0 (advisory) ---
# The jq check uses only shell builtins and runs before the git-repo gate, so a
# bare PATH (no jq, no git) still reaches it; git's absence then trips the
# `|| exit 0` gate. This proves the suite surfaces a missing jq instead of
# letting the jq-based hooks silently fail open undetected.
output=$( PATH="/nonexistent-bin-for-test" /bin/bash "$HOOK" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$output" | grep -q "jq is not installed"; then
    assert_pass "jq missing → fail-open warning surfaced, exit 0"
else
    assert_fail "jq missing: expected warning + exit 0, got rc=$rc output=[$output]"
fi

# --- Test: jq present (normal) → no jq warning ---
output=$( cd "$TMPROOT/clean" && bash "$HOOK" 2>&1 )
if printf '%s' "$output" | grep -q "jq is not installed"; then
    assert_fail "jq present but jq warning printed (false positive)"
else
    assert_pass "jq present → no jq warning (no false positive)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
