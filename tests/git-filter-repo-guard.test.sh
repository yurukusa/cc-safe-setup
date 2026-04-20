#!/bin/bash
# Tests for git-filter-repo-guard.sh
# Run: bash tests/git-filter-repo-guard.test.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/git-filter-repo-guard.sh"

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

echo "git-filter-repo-guard.sh tests"
echo ""

# --- Block: git filter-repo ---
test_hook '{"tool_input":{"command":"git filter-repo --force"}}' 2 "Block git filter-repo --force"
test_hook '{"tool_input":{"command":"git filter-repo --invert-paths --path secret.txt"}}' 2 "Block git filter-repo with path filter"
test_hook '{"tool_input":{"command":"git filter-repo --strip-blobs-bigger-than 10M"}}' 2 "Block git filter-repo blob strip"
test_hook '{"tool_input":{"command":"git filter-repo"}}' 2 "Block bare git filter-repo"

# --- Block: git filter-branch ---
test_hook '{"tool_input":{"command":"git filter-branch --tree-filter rm -f passwords.txt HEAD"}}' 2 "Block git filter-branch --tree-filter"
test_hook '{"tool_input":{"command":"git filter-branch --env-filter"}}' 2 "Block git filter-branch --env-filter"
test_hook '{"tool_input":{"command":"git filter-branch"}}' 2 "Block bare git filter-branch"

# --- Block: BFG Repo-Cleaner ---
test_hook '{"tool_input":{"command":"bfg --strip-blobs-bigger-than 100M"}}' 2 "Block bfg --strip-blobs-bigger-than"
test_hook '{"tool_input":{"command":"bfg --delete-files id_rsa"}}' 2 "Block bfg --delete-files"
test_hook '{"tool_input":{"command":"java -jar bfg.jar --replace-text passwords.txt"}}' 2 "Block bfg.jar via java"

# --- Allow: Safe git commands ---
test_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git status"
test_hook '{"tool_input":{"command":"git log --oneline"}}' 0 "Allow git log"
test_hook '{"tool_input":{"command":"git diff HEAD~3"}}' 0 "Allow git diff"
test_hook '{"tool_input":{"command":"git commit -m fix"}}' 0 "Allow git commit"
test_hook '{"tool_input":{"command":"git push origin main"}}' 0 "Allow git push"
test_hook '{"tool_input":{"command":"git rebase main"}}' 0 "Allow non-interactive rebase"

# --- Allow: Commands containing filter as substring (not filter-repo) ---
test_hook '{"tool_input":{"command":"grep filter README.md"}}' 0 "Allow grep filter"
test_hook '{"tool_input":{"command":"cat filter-config.json"}}' 0 "Allow cat filter-config.json"

# --- Allow: Empty/missing input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_input":{}}' 0 "Allow missing command"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
