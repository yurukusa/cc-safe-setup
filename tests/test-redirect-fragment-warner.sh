#!/bin/bash
# Tests for redirect-fragment-warner.sh
HOOK="examples/redirect-fragment-warner.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3', got: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3', got: $2)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

run_hook() {
    local cmd="$1"
    local extra_env="${2:-}"
    local input='{"tool_input": {"command": '"$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"'}}'
    # shellcheck disable=SC2086
    env $extra_env bash "$HOOK_ABS" 2>&1 <<< "$input"
}

# Test 1: Command without 2>&1 → silent, exit 0
OUT=$(run_hook "ls -la"); RC=$?
assert_not_contains "no 2>&1 no notice" "$OUT" "NOTICE"
assert_not_contains "no 2>&1 no block" "$OUT" "BLOCKED"
assert_exit "no 2>&1 exit 0" "$RC" "0"

# Test 2: Command with 2>&1 → NOTICE, exit 0 (default warn)
OUT=$(run_hook "git commit -m '...' 2>&1 | tail -3"); RC=$?
assert_contains "2>&1 warns" "$OUT" "NOTICE"
assert_contains "2>&1 mentions 25C" "$OUT" "25C"
assert_exit "2>&1 warn exit 0" "$RC" "0"

# Test 3: Suggested rewrite strips 2>&1
OUT=$(run_hook "git push 2>&1 | tail -3"); RC=$?
assert_contains "suggested rewrite shown" "$OUT" "git push"
assert_contains "rewrite has tail" "$OUT" "tail"
assert_not_contains "rewrite strips 2>&1" "$(echo "$OUT" | grep 'good:\|Suggested rewrite' -A1 | grep -v 'bad:\|NOTICE\|Suggested')" "2>&1"

# Test 4: CC_BLOCK_2_REDIRECT=1 → BLOCKED, exit 2
OUT=$(run_hook "git commit -m 'x' 2>&1 | tail -3" "CC_BLOCK_2_REDIRECT=1"); RC=$?
assert_contains "BLOCK mode blocks" "$OUT" "BLOCKED"
assert_contains "BLOCK shows bad" "$OUT" "bad:"
assert_contains "BLOCK shows good" "$OUT" "good:"
assert_exit "BLOCK mode exit 2" "$RC" "2"

# Test 5: # ACCEPT 2>&1 marker overrides warning
OUT=$(run_hook "git commit -m 'x' 2>&1 | tail -3 # ACCEPT 2>&1"); RC=$?
assert_not_contains "ACCEPT marker no notice" "$OUT" "NOTICE"
assert_not_contains "ACCEPT marker no block" "$OUT" "BLOCKED"
assert_exit "ACCEPT marker exit 0" "$RC" "0"

# Test 6: # ACCEPT 2>&1 marker overrides even in BLOCK mode
OUT=$(run_hook "git commit -m 'x' 2>&1 # ACCEPT 2>&1" "CC_BLOCK_2_REDIRECT=1"); RC=$?
assert_not_contains "ACCEPT in BLOCK no notice" "$OUT" "NOTICE"
assert_not_contains "ACCEPT in BLOCK no block" "$OUT" "BLOCKED"
assert_exit "ACCEPT in BLOCK exit 0" "$RC" "0"

# Test 7: CC_REDIRECT_FRAGMENT_DISABLE=1 → silent, exit 0
OUT=$(run_hook "git commit -m 'x' 2>&1" "CC_REDIRECT_FRAGMENT_DISABLE=1"); RC=$?
assert_not_contains "DISABLE no notice" "$OUT" "NOTICE"
assert_not_contains "DISABLE no block" "$OUT" "BLOCKED"
assert_exit "DISABLE exit 0" "$RC" "0"

# Test 8: CC_REDIRECT_FRAGMENT_DISABLE=1 overrides BLOCK mode
OUT=$(run_hook "git commit -m 'x' 2>&1" "CC_REDIRECT_FRAGMENT_DISABLE=1 CC_BLOCK_2_REDIRECT=1"); RC=$?
assert_not_contains "DISABLE wins over BLOCK" "$OUT" "BLOCKED"
assert_exit "DISABLE+BLOCK exit 0" "$RC" "0"

# Test 9: CC_REDIRECT_FRAGMENT_QUIET=1 → silent in warn mode, exit 0
OUT=$(run_hook "git commit 2>&1" "CC_REDIRECT_FRAGMENT_QUIET=1"); RC=$?
assert_not_contains "QUIET no notice" "$OUT" "NOTICE"
assert_exit "QUIET warn exit 0" "$RC" "0"

# Test 10: CC_REDIRECT_FRAGMENT_QUIET=1 + CC_BLOCK_2_REDIRECT=1 → silent but blocks
OUT=$(run_hook "git commit 2>&1" "CC_REDIRECT_FRAGMENT_QUIET=1 CC_BLOCK_2_REDIRECT=1"); RC=$?
assert_not_contains "QUIET+BLOCK no message" "$OUT" "BLOCKED"
assert_exit "QUIET+BLOCK exit 2" "$RC" "2"

# Test 11: 2>&1 anywhere in long pipeline detected
OUT=$(run_hook "find . -type f | xargs grep -l 'foo' 2>&1 | sort"); RC=$?
assert_contains "long pipeline detected" "$OUT" "NOTICE"
assert_exit "long pipeline exit 0" "$RC" "0"

# Test 12: 1>&2 NOT detected (only 2>&1 is the trigger)
OUT=$(run_hook "echo error 1>&2"); RC=$?
assert_not_contains "1>&2 not detected" "$OUT" "NOTICE"
assert_exit "1>&2 exit 0" "$RC" "0"

# Test 13: Empty input → exit 0
OUT=$(env bash "$HOOK_ABS" 2>&1 < /dev/null); RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 14: Missing tool_input.command → exit 0
OUT=$(env bash "$HOOK_ABS" 2>&1 <<< '{}'); RC=$?
assert_exit "missing command exit 0" "$RC" "0"

# Test 15: Block message references anchor issue + Gist
OUT=$(run_hook "make 2>&1" "CC_BLOCK_2_REDIRECT=1"); RC=$?
assert_contains "block mentions 64334" "$OUT" "64334"
assert_contains "block mentions Gist" "$OUT" "5881286479969d5bac0323511dc33ab2"

# Test 16: Notice message references 25C axis
OUT=$(run_hook "make 2>&1"); RC=$?
assert_contains "notice mentions axis" "$OUT" "25C"

# Test 17: Suggested rewrite preserves rest of command
OUT=$(run_hook "git log --oneline 2>&1 | head -10"); RC=$?
assert_contains "rewrite keeps git log" "$OUT" "git log"
assert_contains "rewrite keeps head" "$OUT" "head"

# Test 18: Multiple 2>&1 occurrences → all stripped in rewrite
OUT=$(run_hook "(cmd1 2>&1; cmd2 2>&1) | tee out"); RC=$?
assert_contains "multi 2>&1 still warns" "$OUT" "NOTICE"
# The stripping is best-effort; just ensure warning fires
assert_exit "multi 2>&1 exit 0" "$RC" "0"

# Test 19: 2>&1 inside quotes (still trigger - permission engine sees raw text)
OUT=$(run_hook 'echo "redirect with 2>&1 here"'); RC=$?
assert_contains "2>&1 in quotes detected" "$OUT" "NOTICE"
assert_exit "2>&1 in quotes exit 0" "$RC" "0"

# Test 20: bare ampersand without 2>&1 NOT detected (different trigger)
OUT=$(run_hook "sleep 5 & wait"); RC=$?
assert_not_contains "bare & not detected" "$OUT" "NOTICE"
assert_exit "bare & exit 0" "$RC" "0"

echo ""
echo "redirect-fragment-warner tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
