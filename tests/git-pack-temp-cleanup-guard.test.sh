#!/bin/bash
# Tests for git-pack-temp-cleanup-guard.sh
# Run: bash tests/git-pack-temp-cleanup-guard.test.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")" && pwd)/../examples/git-pack-temp-cleanup-guard.sh"

run_hook() {
    local input="$1" expected_exit="$2" desc="$3" extra_env="${4:-}"
    local actual_exit=0
    local stderr_out
    if [ -n "$extra_env" ]; then
        # shellcheck disable=SC2086
        stderr_out=$(echo "$input" | env $extra_env bash "$HOOK" 2>&1 >/dev/null) || actual_exit=$?
    else
        stderr_out=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null) || actual_exit=$?
    fi
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        echo "    stderr: $stderr_out"
        FAIL=$((FAIL + 1))
    fi
}

# Each test sets up an isolated git repo in a temp dir so we never
# touch the user's real .git directory.
setup_repo() {
    local dir
    dir=$(mktemp -d)
    (cd "$dir" && git init -q)
    echo "$dir"
}

teardown_repo() {
    rm -rf "$1"
}

echo "git-pack-temp-cleanup-guard.sh tests"
echo ""

# --- No-op cases ---
run_hook '{}' 0 "Allow empty input"
run_hook '{"tool_input":{}}' 0 "Allow missing command"
run_hook '{"tool_input":{"command":"echo hello"}}' 0 "Allow non-git command"
run_hook '{"tool_input":{"command":"ls -la"}}' 0 "Allow ls command"

# --- Git commands outside a repo ---
TMP=$(mktemp -d)
pushd "$TMP" >/dev/null
run_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git command outside a repo (no .git found)"
popd >/dev/null
rm -rf "$TMP"

# --- Git commands inside a clean repo (no tmp_pack_*) ---
REPO=$(setup_repo)
pushd "$REPO" >/dev/null
run_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git status in clean repo"
run_hook '{"tool_input":{"command":"git log"}}' 0 "Allow git log in clean repo"
run_hook '{"tool_input":{"command":"git commit -m fix"}}' 0 "Allow git commit in clean repo"
popd >/dev/null
teardown_repo "$REPO"

# --- Cleanup of stale tmp_pack_* (older than threshold) ---
REPO=$(setup_repo)
mkdir -p "$REPO/.git/objects/pack"
# Create a fake stale tmp_pack_ file. Use touch -d to backdate it 2 hours.
touch -d "2 hours ago" "$REPO/.git/objects/pack/tmp_pack_stale1"
touch -d "2 hours ago" "$REPO/.git/objects/pack/tmp_pack_stale2"
echo "x" > "$REPO/.git/objects/pack/tmp_pack_stale1"
touch -d "2 hours ago" "$REPO/.git/objects/pack/tmp_pack_stale1"
pushd "$REPO" >/dev/null
run_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git status, stale tmp_pack_* should be removed"
remaining=$(find "$REPO/.git/objects/pack" -name 'tmp_pack_*' | wc -l)
if [ "$remaining" -eq 0 ]; then
    echo "  PASS: stale tmp_pack_* removed"
    PASS=$((PASS + 1))
else
    echo "  FAIL: $remaining stale tmp_pack_* still present"
    FAIL=$((FAIL + 1))
fi
popd >/dev/null
teardown_repo "$REPO"

# --- Recent tmp_pack_* must NOT be removed ---
REPO=$(setup_repo)
mkdir -p "$REPO/.git/objects/pack"
echo "x" > "$REPO/.git/objects/pack/tmp_pack_fresh"
pushd "$REPO" >/dev/null
run_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git status, recent tmp_pack_* preserved"
remaining=$(find "$REPO/.git/objects/pack" -name 'tmp_pack_*' | wc -l)
if [ "$remaining" -eq 1 ]; then
    echo "  PASS: recent tmp_pack_* preserved"
    PASS=$((PASS + 1))
else
    echo "  FAIL: recent tmp_pack_* changed (remaining=$remaining)"
    FAIL=$((FAIL + 1))
fi
popd >/dev/null
teardown_repo "$REPO"

# --- Block when tmp_pack_* total exceeds CC_GIT_PACK_BLOCK_GB ---
# Use a tiny block threshold so a small synthetic file trips it.
REPO=$(setup_repo)
mkdir -p "$REPO/.git/objects/pack"
# Create a 2 MiB recent file; with CC_GIT_PACK_BLOCK_GB=0 even the
# smallest non-empty tmp_pack_ trips the block branch (>= 0 GiB).
dd if=/dev/zero of="$REPO/.git/objects/pack/tmp_pack_big" bs=1M count=2 status=none
pushd "$REPO" >/dev/null
run_hook '{"tool_input":{"command":"git status"}}' 2 "Block when remaining > block threshold" "CC_GIT_PACK_BLOCK_GB=0 CC_GIT_PACK_AGE_MIN=10000"
popd >/dev/null
teardown_repo "$REPO"

# --- DISABLE flag should bypass everything ---
REPO=$(setup_repo)
mkdir -p "$REPO/.git/objects/pack"
dd if=/dev/zero of="$REPO/.git/objects/pack/tmp_pack_big" bs=1M count=2 status=none
pushd "$REPO" >/dev/null
run_hook '{"tool_input":{"command":"git status"}}' 0 "DISABLE flag bypasses all checks" "CC_GIT_PACK_DISABLE=1 CC_GIT_PACK_BLOCK_GB=0"
popd >/dev/null
teardown_repo "$REPO"

# --- Non-git binaries with 'git' substring ---
run_hook '{"tool_input":{"command":"echo /usr/local/lib/gitlab"}}' 0 "Allow path with 'gitlab' substring"
run_hook '{"tool_input":{"command":"npm install gitignore-cli"}}' 0 "Allow npm install with gitignore-cli"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
