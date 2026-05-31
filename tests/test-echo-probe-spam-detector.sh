#!/bin/bash
# Tests for echo-probe-spam-detector.sh
HOOK="examples/echo-probe-spam-detector.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3', got: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3', got: $2)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

# Isolate state per test via unique TMPDIR + session ID
run_hook() {
    local sid="$1"
    local cmd="$2"
    local extra_env="${3:-}"
    local input='{"tool_input": {"command": '"$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"'}}'
    # shellcheck disable=SC2086
    env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="$sid" $extra_env bash "$HOOK_ABS" 2>&1 <<< "$input"
}
run_hook_with_rc() {
    local sid="$1"
    local cmd="$2"
    local extra_env="${3:-}"
    local input='{"tool_input": {"command": '"$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"'}}'
    env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="$sid" $extra_env bash "$HOOK_ABS" 2>&1 <<< "$input"
    return $?
}

# Test 1: Non-probe command exits 0 silently (no counter increment)
OUT=$(run_hook "s1" "ls -la"); RC=$?
assert_not_contains "non-probe no notice" "$OUT" "NOTICE"
assert_not_contains "non-probe no block" "$OUT" "BLOCKED"
assert_exit "non-probe exit 0" "$RC" "0"

# Test 2: First echo s1 → NOTICE, exit 0
OUT=$(run_hook "s2" "echo s1"); RC=$?
assert_contains "echo s1 notice" "$OUT" "NOTICE"
assert_contains "echo s1 mentions 1/3" "$OUT" "1/3"
assert_exit "echo s1 first exit 0" "$RC" "0"

# Test 3: Second echo s2 → NOTICE 2/3, exit 0
OUT=$(run_hook "s2" "echo s2"); RC=$?
assert_contains "echo s2 notice 2" "$OUT" "2/3"
assert_exit "echo s2 second exit 0" "$RC" "0"

# Test 4: Third echo s3 → BLOCKED, exit 2
OUT=$(run_hook "s2" "echo s3"); RC=$?
assert_contains "echo s3 blocked" "$OUT" "BLOCKED"
assert_exit "echo s3 third exit 2" "$RC" "2"

# Test 5: Non-probe in middle resets counter
OUT=$(run_hook "s3" "echo s1"); _=$?  # 1
OUT=$(run_hook "s3" "ls"); _=$?       # reset
OUT=$(run_hook "s3" "echo s1"); RC=$?  # back to 1
assert_contains "after reset count 1" "$OUT" "1/3"
assert_exit "after reset exit 0" "$RC" "0"

# Test 6: CC_ECHO_PROBE_DISABLE=1 → never warn or block
OUT=$(run_hook "s4" "echo s1" "CC_ECHO_PROBE_DISABLE=1"); RC=$?
assert_not_contains "DISABLE no notice" "$OUT" "NOTICE"
assert_exit "DISABLE exit 0" "$RC" "0"
OUT=$(run_hook "s4" "echo s2" "CC_ECHO_PROBE_DISABLE=1"); _=$?
OUT=$(run_hook "s4" "echo s3" "CC_ECHO_PROBE_DISABLE=1"); RC=$?
assert_not_contains "DISABLE no block" "$OUT" "BLOCKED"
assert_exit "DISABLE 3rd exit 0" "$RC" "0"

# Test 7: CC_ECHO_PROBE_QUIET=1 → silent but still blocks
OUT=$(run_hook "s5" "echo s1" "CC_ECHO_PROBE_QUIET=1"); RC=$?
assert_not_contains "QUIET no notice 1" "$OUT" "NOTICE"
assert_exit "QUIET 1st exit 0" "$RC" "0"
OUT=$(run_hook "s5" "echo s2" "CC_ECHO_PROBE_QUIET=1"); _=$?
OUT=$(run_hook "s5" "echo s3" "CC_ECHO_PROBE_QUIET=1"); RC=$?
assert_not_contains "QUIET no block message" "$OUT" "BLOCKED"
assert_exit "QUIET 3rd exit 2" "$RC" "2"

# Test 8: CC_ECHO_PROBE_THRESHOLD=2 → block at 2
OUT=$(run_hook "s6" "echo s1" "CC_ECHO_PROBE_THRESHOLD=2"); RC=$?
assert_contains "T=2 first 1/2" "$OUT" "1/2"
assert_exit "T=2 first exit 0" "$RC" "0"
OUT=$(run_hook "s6" "echo s2" "CC_ECHO_PROBE_THRESHOLD=2"); RC=$?
assert_contains "T=2 second blocks" "$OUT" "BLOCKED"
assert_exit "T=2 second exit 2" "$RC" "2"

# Test 9: Short echo args (1-3 chars) detected
OUT=$(run_hook "s7" "echo x"); RC=$?
assert_contains "short arg detected" "$OUT" "NOTICE"
assert_exit "short arg exit 0" "$RC" "0"

# Test 10: Real echo with longer message NOT detected
OUT=$(run_hook "s8" 'echo "Build successful"'); RC=$?
assert_not_contains "real echo no notice" "$OUT" "NOTICE"
assert_exit "real echo exit 0" "$RC" "0"

# Test 11: sleep N; echo X detected
OUT=$(run_hook "s9" "sleep 1; echo flush"); RC=$?
assert_contains "sleep+echo detected" "$OUT" "NOTICE"
assert_exit "sleep+echo exit 0" "$RC" "0"

# Test 12: # RESET ECHO PROBE marker clears state
OUT=$(run_hook "s10" "echo s1"); _=$?  # 1
OUT=$(run_hook "s10" "echo s2"); _=$?  # 2
OUT=$(run_hook "s10" "ls # RESET ECHO PROBE"); RC=$?
assert_exit "RESET marker exit 0" "$RC" "0"
OUT=$(run_hook "s10" "echo s1"); RC=$?
assert_contains "after RESET count 1" "$OUT" "1/3"

# Test 13: Empty input → exit 0
OUT=$(env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="s11" bash "$HOOK_ABS" 2>&1 < /dev/null); RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 14: Missing tool_input.command → exit 0
OUT=$(env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="s12" bash "$HOOK_ABS" 2>&1 <<< '{}'); RC=$?
assert_exit "missing command exit 0" "$RC" "0"

# Test 15: Different session IDs have independent counters
OUT=$(run_hook "sess-A" "echo s1"); _=$?
OUT=$(run_hook "sess-A" "echo s2"); _=$?
OUT=$(run_hook "sess-B" "echo s1"); RC=$?
assert_contains "session B count 1" "$OUT" "1/3"

# Test 16: Block message includes anchor issue + Gist reference
run_hook "s13" "echo s1" > /dev/null
run_hook "s13" "echo s2" > /dev/null
OUT=$(run_hook "s13" "echo s3"); RC=$?
assert_contains "block mentions issue 63887" "$OUT" "63887"
assert_contains "block mentions Gist" "$OUT" "5881286479969d5bac0323511dc33ab2"

# Test 17: 4-char echo argument NOT detected (above threshold)
OUT=$(run_hook "s14" "echo abcd"); RC=$?
assert_not_contains "4-char echo not detected" "$OUT" "NOTICE"
assert_exit "4-char echo exit 0" "$RC" "0"

# Test 18: echo without arg NOT detected (non-probe shape)
OUT=$(run_hook "s15" "echo"); RC=$?
assert_not_contains "bare echo not detected" "$OUT" "NOTICE"
assert_exit "bare echo exit 0" "$RC" "0"

echo ""
echo "echo-probe-spam-detector tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
