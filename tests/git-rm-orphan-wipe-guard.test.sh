#!/bin/bash
# Tests for git-rm-orphan-wipe-guard.sh
# Run: bash tests/git-rm-orphan-wipe-guard.test.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/git-rm-orphan-wipe-guard.sh"

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

echo "git-rm-orphan-wipe-guard.sh tests"
echo ""

# --- Block: the #70687 compound command ---
test_hook '{"tool_input":{"command":"git checkout --orphan wipe && git rm -rf . --quiet"}}' 2 "Block the #70687 orphan+rm compound"

# --- Block: git checkout/switch --orphan ---
test_hook '{"tool_input":{"command":"git checkout --orphan newroot"}}' 2 "Block git checkout --orphan"
test_hook '{"tool_input":{"command":"git switch --orphan fresh"}}' 2 "Block git switch --orphan"
test_hook '{"tool_input":{"command":"git checkout --orphan"}}' 2 "Block bare git checkout --orphan"

# --- Block: recursive git rm ---
test_hook '{"tool_input":{"command":"git rm -rf ."}}' 2 "Block git rm -rf ."
test_hook '{"tool_input":{"command":"git rm -r src"}}' 2 "Block git rm -r <dir>"
test_hook '{"tool_input":{"command":"git rm -fr ."}}' 2 "Block git rm -fr ."
test_hook '{"tool_input":{"command":"git rm --recursive build"}}' 2 "Block git rm --recursive"

# --- Block: whole-tree target without -r ---
test_hook '{"tool_input":{"command":"git rm ."}}' 2 "Block git rm ."
test_hook '{"tool_input":{"command":"git rm *"}}' 2 "Block git rm *"

# --- Allow: --cached (untracks only, disk files survive) ---
test_hook '{"tool_input":{"command":"git rm -r --cached ."}}' 0 "Allow git rm -r --cached . (untrack, no disk loss)"
test_hook '{"tool_input":{"command":"git rm --cached secrets.env"}}' 0 "Allow git rm --cached <file>"

# --- Allow: single-file git rm ---
test_hook '{"tool_input":{"command":"git rm old.txt"}}' 0 "Allow git rm <file>"
test_hook '{"tool_input":{"command":"git rm path/to/file.js"}}' 0 "Allow git rm <path/file>"

# --- Allow: safe git / unrelated commands ---
test_hook '{"tool_input":{"command":"git checkout main"}}' 0 "Allow git checkout <branch>"
test_hook '{"tool_input":{"command":"git switch feature"}}' 0 "Allow git switch <branch>"
test_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git status"
test_hook '{"tool_input":{"command":"git commit -m fix"}}' 0 "Allow git commit"
test_hook '{"tool_input":{"command":"grep orphan README.md"}}' 0 "Allow grep orphan (substring, not git)"
test_hook '{"tool_input":{"command":"rm -rf node_modules"}}' 0 "Allow plain rm (rm-safety-net territory, not this guard)"

# --- Allow: empty/missing input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_input":{}}' 0 "Allow missing command"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
