#!/bin/bash
# Tests for remote-control-billing-classifier.sh
HOOK="examples/remote-control-billing-classifier.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

# Test 1: No remote-control ancestor (override empty) → silent pass
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="bash,login -p,init" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "no remote-control no warning" "$OUT" "remote-control"
assert_exit "no remote-control exit 0" "$RC" "0"

# Test 2: remote-control in ancestor cmdline → advisory + exit 0
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="bash,/home/user/.local/bin/claude remote-control,init" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "remote-control triggers advisory" "$OUT" "remote-control"
assert_contains "advisory names Pool 2" "$OUT" "Pool 2"
assert_contains "advisory cites issue" "$OUT" "#59823"
assert_contains "advisory cites June 15" "$OUT" "2026-06-15"
assert_exit "advisory does not block (exit 0)" "$RC" "0"

# Test 3: Disable env var skips even when remote-control is present
OUT=$(CC_REMOTE_CONTROL_DISABLE=1 \
      CC_REMOTE_CONTROL_PROCESS_OVERRIDE="claude remote-control" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "disable suppresses advisory" "$OUT" "remote-control"
assert_exit "disable exit 0" "$RC" "0"

# Test 4: Pattern override matches custom string
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="my-automation-runner --headless" \
      CC_REMOTE_CONTROL_PATTERN="my-automation-runner" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "custom pattern triggers advisory" "$OUT" "remote-control"
assert_exit "custom pattern exit 0" "$RC" "0"

# Test 5: Pattern does not match arbitrary "remote" string
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="git remote update,bash" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "git remote does not trigger" "$OUT" "remote-control"
assert_exit "git remote exit 0" "$RC" "0"

# Test 6: Advisory includes the two pre-June-15 audits
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="claude remote-control" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "advisory names ps audit" "$OUT" "pgrep"
assert_contains "advisory names opt-in audit" "$OUT" "opt-in"

# Test 7: Hook reads and ignores stdin payload (does not hang)
PAYLOAD='{"hook_event_name":"SessionStart","session_id":"abc"}'
OUT=$(echo "$PAYLOAD" | \
      CC_REMOTE_CONTROL_PROCESS_OVERRIDE="claude remote-control" \
      bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "stdin consumed without breakage" "$OUT" "Pool 2"
assert_exit "stdin path exit 0" "$RC" "0"

# Test 8: Empty override and no live remote-control → silent pass
# (live ps may or may not find remote-control on the test host; we
# only assert that an explicitly-empty override yields no advisory.)
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="bash" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "empty override no advisory" "$OUT" "remote-control"
assert_exit "empty override exit 0" "$RC" "0"

# Test 9: Multiple ancestors, only one matches → advisory
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="bash,sshd,claude remote-control --port 9999,init" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "matching ancestor triggers advisory" "$OUT" "Pool 2"
assert_exit "multi-ancestor exit 0" "$RC" "0"

# Test 10: Disable still consumes stdin (no broken pipe)
PAYLOAD='{"hook_event_name":"SessionStart"}'
OUT=$(echo "$PAYLOAD" | \
      CC_REMOTE_CONTROL_DISABLE=1 \
      CC_REMOTE_CONTROL_PROCESS_OVERRIDE="claude remote-control" \
      bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable with stdin no output" "$OUT" "Pool 2"
assert_exit "disable with stdin exit 0" "$RC" "0"

# Test 11: Pattern is anchored substring (not full regex by default)
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="something-claude remote-control-something,bash" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "substring match triggers" "$OUT" "Pool 2"
assert_exit "substring match exit 0" "$RC" "0"

# Test 12: Advisory mentions cc-safe-setup setup hint indirectly
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="claude remote-control" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "advisory points at silence path" "$OUT" "CC_REMOTE_CONTROL_DISABLE"

# Test 13: Live ps path runs without error when override is unset
unset CC_REMOTE_CONTROL_PROCESS_OVERRIDE
OUT=$(bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
# Cannot assert advisory content (host-dependent); only that exit is 0.
assert_exit "live ps path exit 0" "$RC" "0"

# Test 14: Forest-style ancestor (real-shape) triggers advisory
ANCESTOR="bash,/home/user/.local/bin/claude remote-control,/home/user/.local/share/claude/versions/2.1.143 --print --sdk-url https://api.anthropic.com/v1/code/sessions/abc --session-id xyz"
OUT=$(CC_REMOTE_CONTROL_PROCESS_OVERRIDE="$ANCESTOR" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "real-shape ancestor triggers" "$OUT" "Pool 2"
assert_contains "real-shape advisory cites #59823" "$OUT" "#59823"
assert_exit "real-shape exit 0" "$RC" "0"

# Test 15: Disable env wins over presence
OUT=$(CC_REMOTE_CONTROL_DISABLE=1 \
      CC_REMOTE_CONTROL_PROCESS_OVERRIDE="$ANCESTOR" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "disable over presence" "$OUT" "Pool 2"
assert_exit "disable over presence exit 0" "$RC" "0"

# Test 16: Pattern override + disable still silent
OUT=$(CC_REMOTE_CONTROL_DISABLE=1 \
      CC_REMOTE_CONTROL_PATTERN="x-runner" \
      CC_REMOTE_CONTROL_PROCESS_OVERRIDE="x-runner" \
      bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_not_contains "disable beats custom pattern" "$OUT" "Pool 2"
assert_exit "disable beats custom pattern exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
