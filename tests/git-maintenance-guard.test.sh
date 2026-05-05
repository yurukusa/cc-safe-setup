#!/bin/bash
# Tests for git-maintenance-guard.sh
# Run: bash tests/git-maintenance-guard.test.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/git-maintenance-guard.sh"

run_hook() {
    local input="$1" expected_exit="$2" desc="$3" extra_env="${4:-}"
    local actual_exit=0
    if [ -n "$extra_env" ]; then
        # shellcheck disable=SC2086
        echo "$input" | env $extra_env bash "$HOOK" >/dev/null 2>/dev/null || actual_exit=$?
    else
        echo "$input" | bash "$HOOK" >/dev/null 2>/dev/null || actual_exit=$?
    fi
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "git-maintenance-guard.sh tests"
echo ""

# --- Block git gc ---
run_hook '{"tool_input":{"command":"git gc"}}' 2 "Block bare git gc"
run_hook '{"tool_input":{"command":"git gc --auto"}}' 2 "Block git gc --auto"
run_hook '{"tool_input":{"command":"git gc --aggressive"}}' 2 "Block git gc --aggressive"
run_hook '{"tool_input":{"command":"git gc --prune=now"}}' 2 "Block git gc --prune=now"
run_hook '{"tool_input":{"command":"cd ~/repo && git gc"}}' 2 "Block git gc after cd"

# --- Block git repack ---
run_hook '{"tool_input":{"command":"git repack"}}' 2 "Block bare git repack"
run_hook '{"tool_input":{"command":"git repack -a -d"}}' 2 "Block git repack -a -d"
run_hook '{"tool_input":{"command":"git repack -A -d --depth=250 --window=250"}}' 2 "Block heavy git repack"

# --- Block git maintenance ---
run_hook '{"tool_input":{"command":"git maintenance run"}}' 2 "Block git maintenance run"
run_hook '{"tool_input":{"command":"git maintenance start"}}' 2 "Block git maintenance start"
run_hook '{"tool_input":{"command":"git maintenance stop"}}' 2 "Block git maintenance stop"
run_hook '{"tool_input":{"command":"git maintenance register"}}' 2 "Block git maintenance register"

# --- Block git prune ---
run_hook '{"tool_input":{"command":"git prune"}}' 2 "Block bare git prune"
run_hook '{"tool_input":{"command":"git prune --expire=now"}}' 2 "Block git prune --expire=now"
run_hook '{"tool_input":{"command":"git prune-packed"}}' 2 "Block git prune-packed"

# --- Allow safe git commands ---
run_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git status"
run_hook '{"tool_input":{"command":"git log --oneline"}}' 0 "Allow git log"
run_hook '{"tool_input":{"command":"git commit -m fix"}}' 0 "Allow git commit"
run_hook '{"tool_input":{"command":"git push"}}' 0 "Allow git push"
run_hook '{"tool_input":{"command":"git fetch"}}' 0 "Allow git fetch"
run_hook '{"tool_input":{"command":"git pull"}}' 0 "Allow git pull"
run_hook '{"tool_input":{"command":"git checkout main"}}' 0 "Allow git checkout"
run_hook '{"tool_input":{"command":"git rebase main"}}' 0 "Allow git rebase"
run_hook '{"tool_input":{"command":"git count-objects -v"}}' 0 "Allow git count-objects"
run_hook '{"tool_input":{"command":"git fsck"}}' 0 "Allow git fsck"
run_hook '{"tool_input":{"command":"git verify-pack -v test.idx"}}' 0 "Allow git verify-pack"

# --- Allow unrelated commands containing the words ---
run_hook '{"tool_input":{"command":"echo gc"}}' 0 "Allow non-git gc"
run_hook '{"tool_input":{"command":"echo repack"}}' 0 "Allow non-git repack"
run_hook '{"tool_input":{"command":"echo maintenance"}}' 0 "Allow non-git maintenance"
run_hook '{"tool_input":{"command":"prune-old-files.sh"}}' 0 "Allow non-git prune"

# --- Override flags ---
run_hook '{"tool_input":{"command":"git gc"}}' 0 "ALLOW flag bypasses block" "CC_GIT_MAINTENANCE_ALLOW=1"
run_hook '{"tool_input":{"command":"git repack"}}' 0 "DISABLE flag bypasses block" "CC_GIT_MAINTENANCE_DISABLE=1"

# --- Empty / missing input ---
run_hook '{}' 0 "Allow empty input"
run_hook '{"tool_input":{}}' 0 "Allow missing command"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
