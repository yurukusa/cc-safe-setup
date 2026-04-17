#!/bin/bash
# Tests for home-critical-bash-guard.sh
# Run: bash tests/test-home-critical-bash-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/home-critical-bash-guard.sh"

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

echo "home-critical-bash-guard.sh tests"
echo ""

# --- Block: rm on critical paths ---
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.ssh\"}}" 2 "Block rm -rf ~/.ssh"
test_hook "{\"tool_input\":{\"command\":\"rm $HOME/.git-credentials\"}}" 2 "Block rm ~/.git-credentials"
test_hook "{\"tool_input\":{\"command\":\"rm -f $HOME/.bashrc\"}}" 2 "Block rm ~/.bashrc"
test_hook "{\"tool_input\":{\"command\":\"sudo rm $HOME/.zshrc\"}}" 2 "Block sudo rm ~/.zshrc"
test_hook "{\"tool_input\":{\"command\":\"rm $HOME/.npmrc\"}}" 2 "Block rm ~/.npmrc"
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.gnupg\"}}" 2 "Block rm -rf ~/.gnupg"
test_hook "{\"tool_input\":{\"command\":\"rm $HOME/.aws/credentials\"}}" 2 "Block rm ~/.aws/credentials"

# --- Block: mv on critical paths ---
test_hook "{\"tool_input\":{\"command\":\"mv $HOME/.bashrc /tmp/\"}}" 2 "Block mv ~/.bashrc"
test_hook "{\"tool_input\":{\"command\":\"mv $HOME/.ssh/config /tmp/bak\"}}" 2 "Block mv ~/.ssh/config"

# --- Block: Truncation via redirect ---
test_hook "{\"tool_input\":{\"command\":\"> $HOME/.bashrc\"}}" 2 "Block > ~/.bashrc truncation"
test_hook "{\"tool_input\":{\"command\":\"echo '' > $HOME/.zshrc\"}}" 2 "Block echo > ~/.zshrc"

# --- Block: chmod 777 on critical files ---
test_hook "{\"tool_input\":{\"command\":\"chmod 777 $HOME/.ssh/id_rsa\"}}" 2 "Block chmod 777 on .ssh/id_rsa"

# --- Allow: Safe commands ---
test_hook '{"tool_input":{"command":"rm -rf node_modules"}}' 0 "Allow rm node_modules"
test_hook '{"tool_input":{"command":"rm /tmp/test.txt"}}' 0 "Allow rm in /tmp"
test_hook '{"tool_input":{"command":"ls -la ~/.ssh"}}' 0 "Allow ls on .ssh (read-only)"
test_hook '{"tool_input":{"command":"cat ~/.bashrc"}}' 0 "Allow cat on .bashrc (read-only)"
test_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git commands"

# --- Allow: Empty input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_input":{}}' 0 "Allow missing command"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
