#!/bin/bash
# Tests for auto-mode-safety-enforcer.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/auto-mode-safety-enforcer.sh"

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

echo "auto-mode-safety-enforcer.sh tests"
echo ""

# --- Block: Critical rm operations ---
test_hook '{"tool_input":{"command":"rm -rf /"}}' 2 "Block rm -rf /"
test_hook '{"tool_input":{"command":"rm -rf ~"}}' 2 "Block rm -rf ~"
test_hook '{"tool_input":{"command":"rm -rf ~/."}}' 2 "Block rm -rf ~/."
test_hook '{"tool_input":{"command":"sudo rm -rf /home"}}' 2 "Block sudo rm -rf /home"
test_hook '{"tool_input":{"command":"rm -rf /etc"}}' 2 "Block rm -rf /etc"
test_hook '{"tool_input":{"command":"rm -rf /usr"}}' 2 "Block rm -rf /usr"
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.ssh\"}}" 2 "Block rm -rf ~/.ssh"
test_hook "{\"tool_input\":{\"command\":\"rm $HOME/.git-credentials\"}}" 2 "Block rm ~/.git-credentials"
test_hook "{\"tool_input\":{\"command\":\"rm -f $HOME/.bashrc\"}}" 2 "Block rm ~/.bashrc"

# --- Block: Disk operations ---
test_hook '{"tool_input":{"command":"sudo dd if=/dev/zero of=/dev/sda"}}' 2 "Block dd to disk"
test_hook '{"tool_input":{"command":"sudo mkfs.ext4 /dev/sda1"}}' 2 "Block mkfs"
test_hook '{"tool_input":{"command":"sudo fdisk /dev/sda"}}' 2 "Block fdisk"

# --- Block: System process kill ---
test_hook '{"tool_input":{"command":"kill -9 1"}}' 2 "Block kill PID 1"
test_hook '{"tool_input":{"command":"killall systemd"}}' 2 "Block killall systemd"

# --- Allow: Safe operations ---
test_hook '{"tool_input":{"command":"rm -rf node_modules"}}' 0 "Allow rm node_modules"
test_hook '{"tool_input":{"command":"rm /tmp/test.txt"}}' 0 "Allow rm in /tmp"
test_hook '{"tool_input":{"command":"ls -la"}}' 0 "Allow ls"
test_hook '{"tool_input":{"command":"git status"}}' 0 "Allow git"
test_hook '{"tool_input":{"command":"npm install"}}' 0 "Allow npm install"
test_hook '{}' 0 "Allow empty input"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
