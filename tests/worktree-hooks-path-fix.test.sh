#!/bin/bash
# Tests for worktree-hooks-path-fix.sh
HOOK="$(dirname "$0")/../examples/worktree-hooks-path-fix.sh"
PASS=0; FAIL=0

TEST_BASE=$(mktemp -d)
cleanup() { rm -rf "$TEST_BASE"; }
trap cleanup EXIT

run_test() {
    local desc="$1" expect_code="$2" check_fn="${3:-}"
    if [ -n "$check_fn" ]; then
        if "$check_fn"; then
            echo "PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $desc"
            FAIL=$((FAIL + 1))
        fi
    fi
}

# === Helper: create a main repo + a Claude-style worktree at known path ===
setup_repo_with_worktree() {
    local main_repo="$1"
    local worktree_subdir="$2"

    rm -rf "$main_repo"
    mkdir -p "$main_repo"
    cd "$main_repo" || return 1
    git init --quiet
    git config user.email "test@test"
    git config user.name "test"
    git commit --allow-empty --quiet -m "init"
    git config extensions.worktreeConfig true
    # Simulate Husky-style shared core.hooksPath
    git config core.hooksPath ".hooks_shared"

    # Create a Claude-style worktree
    local worktree_path="$main_repo/.claude/worktrees/$worktree_subdir"
    mkdir -p "$(dirname "$worktree_path")"
    git worktree add -q "$worktree_path" 2>/dev/null
}

# === Test 1: bogus absolute hooksPath gets unset ===
setup_repo_with_worktree "$TEST_BASE/repo1" "wt1"
WORKTREE="$TEST_BASE/repo1/.claude/worktrees/wt1"
# Write a bogus absolute hooksPath
git -C "$WORKTREE" config --worktree core.hooksPath "/tmp/nonexistent/hooks"

# Run the hook
echo '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$WORKTREE" bash "$HOOK" >/dev/null 2>&1

# Verify the worktree config no longer has core.hooksPath
RESULT=$(git -C "$WORKTREE" config --worktree --get core.hooksPath 2>/dev/null || echo "")
if [ -z "$RESULT" ]; then
    echo "PASS: bogus absolute hooksPath unset"
    PASS=$((PASS + 1))
else
    echo "FAIL: hooksPath still set: $RESULT"
    FAIL=$((FAIL + 1))
fi

# Verify shared config's hooksPath still resolves
SHARED=$(git -C "$WORKTREE" config --get core.hooksPath 2>/dev/null || echo "")
if [ "$SHARED" = ".hooks_shared" ]; then
    echo "PASS: shared hooksPath fell through correctly"
    PASS=$((PASS + 1))
else
    echo "FAIL: shared hooksPath wrong: $SHARED (expected .hooks_shared)"
    FAIL=$((FAIL + 1))
fi

# === Test 2: relative hooksPath is left alone ===
setup_repo_with_worktree "$TEST_BASE/repo2" "wt2"
WORKTREE="$TEST_BASE/repo2/.claude/worktrees/wt2"
git -C "$WORKTREE" config --worktree core.hooksPath ".husky/_"
echo '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$WORKTREE" bash "$HOOK" >/dev/null 2>&1
RESULT=$(git -C "$WORKTREE" config --worktree --get core.hooksPath 2>/dev/null || echo "")
if [ "$RESULT" = ".husky/_" ]; then
    echo "PASS: relative hooksPath left alone"
    PASS=$((PASS + 1))
else
    echo "FAIL: relative hooksPath altered: $RESULT"
    FAIL=$((FAIL + 1))
fi

# === Test 3: absolute path inside worktree is left alone ===
setup_repo_with_worktree "$TEST_BASE/repo3" "wt3"
WORKTREE="$TEST_BASE/repo3/.claude/worktrees/wt3"
INTERNAL_PATH="$WORKTREE/.local-hooks"
git -C "$WORKTREE" config --worktree core.hooksPath "$INTERNAL_PATH"
echo '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$WORKTREE" bash "$HOOK" >/dev/null 2>&1
RESULT=$(git -C "$WORKTREE" config --worktree --get core.hooksPath 2>/dev/null || echo "")
if [ "$RESULT" = "$INTERNAL_PATH" ]; then
    echo "PASS: absolute path inside worktree left alone"
    PASS=$((PASS + 1))
else
    echo "FAIL: internal absolute path altered: $RESULT"
    FAIL=$((FAIL + 1))
fi

# === Test 4: non-worktree (main checkout) is a no-op ===
setup_repo_with_worktree "$TEST_BASE/repo4" "wt4"
MAIN_REPO="$TEST_BASE/repo4"
# Set a bogus hooksPath in main config (per-worktree scope not applicable here, use --local)
git -C "$MAIN_REPO" config core.hooksPath "/tmp/bogus"
echo '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$MAIN_REPO" bash "$HOOK" >/dev/null 2>&1
RESULT=$(git -C "$MAIN_REPO" config --get core.hooksPath 2>/dev/null || echo "")
if [ "$RESULT" = "/tmp/bogus" ]; then
    echo "PASS: main checkout untouched"
    PASS=$((PASS + 1))
else
    echo "FAIL: main checkout altered: $RESULT"
    FAIL=$((FAIL + 1))
fi

# === Test 5: worktree NOT under .claude/worktrees/ is left alone ===
mkdir -p "$TEST_BASE/repo5"
cd "$TEST_BASE/repo5"
git init --quiet
git config user.email t@t; git config user.name t
git commit --allow-empty --quiet -m i
git config extensions.worktreeConfig true
OTHER_WORKTREE="$TEST_BASE/other-wt-location/wt5"
mkdir -p "$(dirname "$OTHER_WORKTREE")"
git worktree add -q "$OTHER_WORKTREE" 2>/dev/null
git -C "$OTHER_WORKTREE" config --worktree core.hooksPath "/tmp/bogus"
echo '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$OTHER_WORKTREE" bash "$HOOK" >/dev/null 2>&1
RESULT=$(git -C "$OTHER_WORKTREE" config --worktree --get core.hooksPath 2>/dev/null || echo "")
if [ "$RESULT" = "/tmp/bogus" ]; then
    echo "PASS: non-Claude worktree path pattern left alone"
    PASS=$((PASS + 1))
else
    echo "FAIL: non-Claude worktree altered: $RESULT"
    FAIL=$((FAIL + 1))
fi

# === Test 6: CC_WORKTREE_HOOKS_FIX_DISABLE bypasses ===
setup_repo_with_worktree "$TEST_BASE/repo6" "wt6"
WORKTREE="$TEST_BASE/repo6/.claude/worktrees/wt6"
git -C "$WORKTREE" config --worktree core.hooksPath "/tmp/bogus6"
echo '{"hook_event_name":"SessionStart"}' | CC_WORKTREE_HOOKS_FIX_DISABLE=1 CLAUDE_PROJECT_DIR="$WORKTREE" bash "$HOOK" >/dev/null 2>&1
RESULT=$(git -C "$WORKTREE" config --worktree --get core.hooksPath 2>/dev/null || echo "")
if [ "$RESULT" = "/tmp/bogus6" ]; then
    echo "PASS: DISABLE env var bypasses hook"
    PASS=$((PASS + 1))
else
    echo "FAIL: DISABLE bypass failed: $RESULT"
    FAIL=$((FAIL + 1))
fi

# === Test 7: non-git directory is a no-op ===
NON_GIT="$TEST_BASE/not-a-repo"
mkdir -p "$NON_GIT"
echo '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$NON_GIT" bash "$HOOK" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" = "0" ]; then
    echo "PASS: non-git directory exits 0"
    PASS=$((PASS + 1))
else
    echo "FAIL: non-git directory exit code: $EXIT_CODE"
    FAIL=$((FAIL + 1))
fi

# === Test 8: empty input is no-op ===
echo '{}' | CLAUDE_PROJECT_DIR="$TEST_BASE/repo6/.claude/worktrees/wt6" bash "$HOOK" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" = "0" ]; then
    echo "PASS: empty event payload exits 0"
    PASS=$((PASS + 1))
else
    echo "FAIL: empty event exit code: $EXIT_CODE"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
