#!/bin/bash
# Tests for git-operations-require-approval.sh
# Run: bash tests/test-git-operations-require-approval.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/git-operations-require-approval.sh"

test_hook() {
    local input="$1" expected_exit="$2" desc="$3"
    local actual_exit=0
    echo "$input" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "git-operations-require-approval.sh tests"
echo ""

# --- Safe commands (exit 0) ---
test_hook '{"tool_input":{"command":"git status"}}' 0 "git status allowed"
test_hook '{"tool_input":{"command":"git log --oneline"}}' 0 "git log allowed"
test_hook '{"tool_input":{"command":"git diff HEAD"}}' 0 "git diff allowed"
test_hook '{"tool_input":{"command":"git show HEAD"}}' 0 "git show allowed"
test_hook '{"tool_input":{"command":"git add src/main.ts"}}' 0 "git add allowed"
test_hook '{"tool_input":{"command":"git stash"}}' 0 "git stash allowed"
test_hook '{"tool_input":{"command":"git fetch origin"}}' 0 "git fetch allowed"
test_hook '{"tool_input":{"command":"git branch -a"}}' 0 "git branch -a (list) allowed"
test_hook '{"tool_input":{"command":"git branch --list"}}' 0 "git branch --list allowed"
test_hook '{"tool_input":{"command":"git branch -d old-branch"}}' 0 "git branch -d (delete) allowed"
test_hook '{"tool_input":{"command":"npm install"}}' 0 "non-git command allowed"

# --- Blocked commands (exit 2) ---
test_hook '{"tool_input":{"command":"git commit -m \"fix bug\""}}' 2 "git commit blocked"
test_hook '{"tool_input":{"command":"git commit --amend"}}' 2 "git commit --amend blocked"
test_hook '{"tool_input":{"command":"git push origin main"}}' 2 "git push blocked"
test_hook '{"tool_input":{"command":"git push --force origin main"}}' 2 "git push --force blocked"
test_hook '{"tool_input":{"command":"git push -f origin feature"}}' 2 "git push -f blocked"
test_hook '{"tool_input":{"command":"git checkout -b new-branch"}}' 2 "git checkout -b blocked"
test_hook '{"tool_input":{"command":"git switch -c feature"}}' 2 "git switch -c blocked"
test_hook '{"tool_input":{"command":"git switch --create feature"}}' 2 "git switch --create blocked"
test_hook '{"tool_input":{"command":"git branch feature-x"}}' 2 "git branch <name> blocked"

# --- Compound commands ---
test_hook '{"tool_input":{"command":"ls && git commit -m test"}}' 2 "compound && with commit blocked"
test_hook '{"tool_input":{"command":"git add . ; git push origin main"}}' 2 "compound ; with push blocked"
test_hook '{"tool_input":{"command":"test -f x || git commit -m y"}}' 2 "compound || with commit blocked"
test_hook '{"tool_input":{"command":"git status && git log"}}' 0 "compound safe commands allowed"

# --- Edge cases ---
test_hook '{"tool_input":{"command":"echo git commit -m test"}}' 0 "echo git commit not blocked"
test_hook '{"tool_input":{"command":"printf git push"}}' 0 "printf git push not blocked"
test_hook '{"tool_input":{"command":""}}' 0 "empty command passes"
test_hook '{}' 0 "empty input passes"


# --- git's own global options between `git` and the verb (#1117) ---
# git -C <dir> push does exactly what git push does. Matching the two as
# adjacent words missed every shape below; all of them ran a real push.
test_hook '{"tool_input":{"command":"git -C /tmp/repo push --force origin main"}}' 2 "git -C <dir> push blocked"
test_hook '{"tool_input":{"command":"git --git-dir=/tmp/r/repo.d push origin main"}}' 2 "git --git-dir=<path> push blocked"
test_hook '{"tool_input":{"command":"git --git-dir /tmp/r/repo.d push origin main"}}' 2 "git --git-dir <path> (separate value) push blocked"
test_hook '{"tool_input":{"command":"git --work-tree=/tmp/w --git-dir=/tmp/r/repo.d push origin main"}}' 2 "two global options before push blocked"
test_hook '{"tool_input":{"command":"git -c user.name=x commit -m x"}}' 2 "git -c <k=v> commit blocked"
test_hook '{"tool_input":{"command":"git -C /tmp/r checkout -b feature"}}' 2 "git -C <dir> checkout -b blocked"
test_hook '{"tool_input":{"command":"git -C /tmp/r switch -c feature"}}' 2 "git -C <dir> switch -c blocked"
test_hook '{"tool_input":{"command":"git -C /tmp/r branch feature"}}' 2 "git -C <dir> branch <name> blocked"
test_hook '{"tool_input":{"command":"git -C /tmp/r branch -a"}}' 0 "git -C <dir> branch -a still a listing"
test_hook '{"tool_input":{"command":"git --no-pager push origin main"}}' 2 "git --no-pager push blocked"
test_hook '{"tool_input":{"command":"/usr/bin/git push origin main"}}' 2 "git invoked by absolute path blocked"

# --- the plumbing form of push ---
test_hook '{"tool_input":{"command":"git send-pack origin main"}}' 2 "git send-pack blocked"
test_hook '{"tool_input":{"command":"git -C /tmp/r send-pack origin main"}}' 2 "git -C <dir> send-pack blocked"

# --- the read-only exemption must cover its own segment only ---
# `^\s*(echo|printf)\s` used to exempt the WHOLE command, so everything after
# a harmless first segment ran unguarded.
test_hook '{"tool_input":{"command":"echo hi && git push origin main"}}' 2 "echo first segment does not exempt a later push"
test_hook '{"tool_input":{"command":"echo start; git push origin main"}}' 2 "echo before ; does not exempt a later push"
test_hook '{"tool_input":{"command":"printf x && git commit -m x"}}' 2 "printf first segment does not exempt a later commit"
test_hook '{"tool_input":{"command":"grep -r \"git push\" ./docs"}}' 0 "grep for the words is not an invocation"

# --- the .git path coincidence ---
# `git --git-dir=/tmp/r/.git push` used to match only because the PATH ended in
# `.git`; the same command with any other git-dir name went through.
test_hook '{"tool_input":{"command":"git --git-dir=/tmp/r/.git push origin main"}}' 2 "git-dir named .git blocked"
test_hook '{"tool_input":{"command":"ls /tmp/r/.git"}}' 0 "a path containing .git is not a push"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
echo "All tests passed!"
