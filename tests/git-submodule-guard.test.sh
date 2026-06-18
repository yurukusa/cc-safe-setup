#!/bin/bash
# Tests for git-submodule-guard.sh
# Verifies that the data-destroying forced deinit (#68920) is blocked,
# while unforced deinit / submodule rm are warn-only.
HOOK="examples/git-submodule-guard.sh"
PASS=0 FAIL=0

HOOK_ABS="$PWD/$HOOK"

# run_hook <command> [env assignments...] -> sets $OUT and $RC
run_hook() {
    local cmd="$1"; shift
    OUT=$(printf '{"tool_input":{"command":"%s"}}' "$cmd" | env "$@" bash "$HOOK_ABS" 2>&1)
    RC=$?
}

assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }
assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }

# Forced deinit must be blocked (exit 2) by default.
run_hook "git submodule deinit -f libs/foo"
assert_exit "forced -f blocks" "$RC" 2
assert_contains "block message cites #68920" "$OUT" "#68920"

run_hook "git submodule deinit --force libs/foo"
assert_exit "forced --force blocks" "$RC" 2

run_hook "git submodule deinit --all -f"
assert_exit "deinit --all -f blocks" "$RC" 2

# Unforced deinit: git's own safety still applies, so warn-only (exit 0).
run_hook "git submodule deinit libs/foo"
assert_exit "unforced deinit warns (exit 0)" "$RC" 0
assert_contains "unforced deinit warns" "$OUT" "WARNING"

# submodule rm: warn-only.
run_hook "git submodule rm libs/foo"
assert_exit "submodule rm warns (exit 0)" "$RC" 0

# Unrelated command: untouched.
run_hook "git status"
assert_exit "unrelated passes" "$RC" 0

# Opt-out: warn-only mode lets the forced deinit through (exit 0).
run_hook "git submodule deinit -f libs/foo" SUBMODULE_DEINIT_BLOCK=0
assert_exit "opt-out warn-only (exit 0)" "$RC" 0
assert_contains "opt-out still warns" "$OUT" "WARNING"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
