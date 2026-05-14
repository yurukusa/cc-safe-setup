#!/bin/bash
# Tests for git-flag-bypass-guard.sh (Issues #59006, #18613, #25270, #52409 prevention)
HOOK="examples/git-flag-bypass-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: Plain `git commit` blocked
OUT=$(echo '{"tool_input":{"command":"git commit -m foo"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "plain commit blocked" "$OUT" "BLOCKED"
assert_exit "plain commit exit 2" "$RC" "2"
unset RC

# Test 2: `git -C /repo commit` blocked (the core bypass case)
OUT=$(echo '{"tool_input":{"command":"git -C /repo commit -m foo"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "-C flag bypass blocked" "$OUT" "BLOCKED"
assert_contains "-C error mentions form" "$OUT" "form: git -C /repo commit -m foo"
assert_exit "-C flag exit 2" "$RC" "2"
unset RC

# Test 3: `git --git-dir=.git --work-tree=. commit` blocked
OUT=$(echo '{"tool_input":{"command":"git --git-dir=.git --work-tree=. commit -m foo"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "=form flags blocked" "$OUT" "BLOCKED"
assert_exit "=form flags exit 2" "$RC" "2"
unset RC

# Test 4: `git -c user.name=foo commit` blocked
OUT=$(echo '{"tool_input":{"command":"git -c user.name=foo commit -m bar"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "-c flag bypass blocked" "$OUT" "BLOCKED"
assert_exit "-c flag exit 2" "$RC" "2"
unset RC

# Test 5: `git --no-pager commit` blocked
OUT=$(echo '{"tool_input":{"command":"git --no-pager commit -m foo"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "--no-pager bypass blocked" "$OUT" "BLOCKED"
assert_exit "--no-pager exit 2" "$RC" "2"
unset RC

# Test 6: `git --git-dir <path> commit` (separate-token form) blocked
OUT=$(echo '{"tool_input":{"command":"git --git-dir .git commit -m foo"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "separate-token --git-dir bypass blocked" "$OUT" "BLOCKED"
assert_exit "separate-token --git-dir exit 2" "$RC" "2"
unset RC

# Test 7: `git log` not blocked
OUT=$(echo '{"tool_input":{"command":"git log --oneline -5"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "git log not blocked" "$OUT" "BLOCKED"
assert_exit "git log exit 0" "$RC" "0"

# Test 8: `git status` not blocked
OUT=$(echo '{"tool_input":{"command":"git -C /repo status"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "git -C status not blocked" "$OUT" "BLOCKED"
assert_exit "git -C status exit 0" "$RC" "0"

# Test 9: Non-git command not affected
OUT=$(echo '{"tool_input":{"command":"ls -la"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "non-git not blocked" "$OUT" "BLOCKED"
assert_exit "non-git exit 0" "$RC" "0"

# Test 10: Empty command exits clean
OUT=$(echo '{"tool_input":{"command":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty command exit 0" "$RC" "0"

# Test 11: Empty input exits clean
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 12: Env-var prefix before git, still detected
OUT=$(echo '{"tool_input":{"command":"GIT_AUTHOR_NAME=x git -C /repo commit"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "env-var prefix detected" "$OUT" "BLOCKED"
assert_exit "env-var prefix exit 2" "$RC" "2"
unset RC

# Test 13: Absolute path to git binary detected
OUT=$(echo '{"tool_input":{"command":"/usr/bin/git -C /repo commit"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "abs path git detected" "$OUT" "BLOCKED"
assert_exit "abs path git exit 2" "$RC" "2"
unset RC

# Test 14: Custom DENY list (push only, commit allowed)
OUT=$(echo '{"tool_input":{"command":"git -C /repo commit"}}' | CC_GIT_FLAG_DENY=push bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "custom deny excludes commit" "$OUT" "BLOCKED"
assert_exit "custom deny commit exit 0" "$RC" "0"

# Test 15: Custom DENY list (push), `git push` is blocked
OUT=$(echo '{"tool_input":{"command":"git -C /repo push origin main"}}' | CC_GIT_FLAG_DENY=push bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "custom deny push blocked" "$OUT" "BLOCKED"
assert_exit "custom deny push exit 2" "$RC" "2"
unset RC

# Test 16: Empty DENY list disables hook
OUT=$(echo '{"tool_input":{"command":"git commit -m foo"}}' | CC_GIT_FLAG_DENY= bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty deny disables" "$OUT" "BLOCKED"
assert_exit "empty deny exit 0" "$RC" "0"

# Test 17: Multiple denied subcommands, comma-separated
OUT=$(echo '{"tool_input":{"command":"git -C /repo reset --hard"}}' | CC_GIT_FLAG_DENY="commit,reset,push" bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "multi-deny reset blocked" "$OUT" "BLOCKED"
assert_exit "multi-deny reset exit 2" "$RC" "2"
unset RC

# Test 18: Only "git" with no subcommand exits clean
OUT=$(echo '{"tool_input":{"command":"git"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "bare git exit 0" "$RC" "0"

# Test 19: References canonical issue in error message
OUT=$(echo '{"tool_input":{"command":"git -C /x commit"}}' | bash "$HOOK" 2>&1) || RC=$?; RC=${RC:-0}
assert_contains "error references #18613" "$OUT" "#18613"
unset RC

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
