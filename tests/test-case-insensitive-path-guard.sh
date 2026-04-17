#!/bin/bash
# Tests for case-insensitive-path-guard.sh
# Run: bash tests/test-case-insensitive-path-guard.sh
# NOTE: Full case-mismatch detection only works on macOS APFS.
#       On Linux, the hook exits 0 for all inputs (no case-insensitive FS).
#       These tests verify the non-macOS path (exit 0) and input parsing.
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/case-insensitive-path-guard.sh"

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

echo "case-insensitive-path-guard.sh tests"
echo ""

# On Linux, all commands should pass through (exit 0)
# The hook only activates on macOS (uname == Darwin)
IS_LINUX=0
[ "$(uname)" != "Darwin" ] && IS_LINUX=1

if [ "$IS_LINUX" -eq 1 ]; then
    echo "Running on Linux — all tests should pass through (exit 0)"
    echo ""

    # --- Pass-through on Linux ---
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/Projects"}}' 0 "Linux: rm -rf passes through"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf ~/Documents"}}' 0 "Linux: rm Documents passes through"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"mv ~/old ~/new"}}' 0 "Linux: mv passes through"

    # --- Non-destructive commands always pass ---
    test_hook '{"tool_name":"Bash","tool_input":{"command":"ls ~/Projects"}}' 0 "Linux: ls passes through"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 0 "Linux: git status passes through"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' 0 "Linux: echo passes through"

    # --- Safe paths always pass ---
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}' 0 "Linux: rm node_modules passes"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"}}' 0 "Linux: rm /tmp passes"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf .cache"}}' 0 "Linux: rm .cache passes"

    # --- Empty/missing inputs ---
    test_hook '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "Empty command"
    test_hook '{"tool_name":"Bash","tool_input":{}}' 0 "No command"
    test_hook '{}' 0 "Empty JSON"

else
    echo "Running on macOS — testing case-mismatch detection"
    echo ""

    # On macOS, safe paths should still pass
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}' 0 "macOS: rm node_modules passes"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"}}' 0 "macOS: rm /tmp passes"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"rm -rf __pycache__"}}' 0 "macOS: rm __pycache__ passes"

    # Non-destructive commands pass
    test_hook '{"tool_name":"Bash","tool_input":{"command":"ls ~/Projects"}}' 0 "macOS: ls passes through"
    test_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 0 "macOS: git status passes"

    # Empty inputs
    test_hook '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "Empty command"
    test_hook '{"tool_name":"Bash","tool_input":{}}' 0 "No command"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || exit 1
