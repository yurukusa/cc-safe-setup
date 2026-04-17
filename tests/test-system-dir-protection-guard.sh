#!/bin/bash
# Tests for system-dir-protection-guard.sh
# Run: bash tests/test-system-dir-protection-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/system-dir-protection-guard.sh"

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

echo "system-dir-protection-guard.sh tests"
echo ""

# --- Block: rm on system directories ---
test_hook '{"tool_input":{"command":"rm -rf /etc"}}' 2 "Block rm -rf /etc"
test_hook '{"tool_input":{"command":"rm -rf /usr"}}' 2 "Block rm -rf /usr"
test_hook '{"tool_input":{"command":"rm -rf /var"}}' 2 "Block rm -rf /var"
test_hook '{"tool_input":{"command":"rm -rf /opt"}}' 2 "Block rm -rf /opt"
test_hook '{"tool_input":{"command":"rm -rf /boot"}}' 2 "Block rm -rf /boot"
test_hook '{"tool_input":{"command":"rm -rf /root"}}' 2 "Block rm -rf /root"
test_hook '{"tool_input":{"command":"rm -rf /srv"}}' 2 "Block rm -rf /srv"
test_hook '{"tool_input":{"command":"rm -rf /home"}}' 2 "Block rm -rf /home"
test_hook '{"tool_input":{"command":"rm -rf /home/username"}}' 2 "Block rm -rf /home/username"
test_hook '{"tool_input":{"command":"sudo rm -rf /etc/nginx"}}' 2 "Block sudo rm -rf /etc/nginx"
test_hook '{"tool_input":{"command":"rm -rf /usr/local"}}' 2 "Block rm -rf /usr/local"

# --- Block: rm on critical home directories ---
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.ssh\"}}" 2 "Block rm -rf ~/.ssh"
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.config\"}}" 2 "Block rm -rf ~/.config"
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.local\"}}" 2 "Block rm -rf ~/.local"
test_hook "{\"tool_input\":{\"command\":\"rm -rf $HOME/.gnupg\"}}" 2 "Block rm -rf ~/.gnupg"

# --- Block: mv on system directories (#49554) ---
test_hook '{"tool_input":{"command":"mv /etc /tmp/etc_backup"}}' 2 "Block mv /etc"
test_hook '{"tool_input":{"command":"mv /usr/local /tmp/"}}' 2 "Block mv /usr/local"
test_hook '{"tool_input":{"command":"mv /home/user /tmp/"}}' 2 "Block mv /home/user"
test_hook '{"tool_input":{"command":"sudo mv /var/lib /tmp/"}}' 2 "Block sudo mv /var/lib"
test_hook "{\"tool_input\":{\"command\":\"mv $HOME/.ssh /tmp/\"}}" 2 "Block mv ~/.ssh"

# --- Block: chmod -R on system directories ---
test_hook '{"tool_input":{"command":"chmod -R 777 /etc"}}' 2 "Block chmod -R 777 /etc"
test_hook '{"tool_input":{"command":"sudo chmod -R 755 /usr"}}' 2 "Block sudo chmod -R /usr"

# --- Block: chown -R on system directories ---
test_hook '{"tool_input":{"command":"chown -R user:user /var"}}' 2 "Block chown -R /var"
test_hook '{"tool_input":{"command":"sudo chown -R root:root /opt"}}' 2 "Block sudo chown -R /opt"

# --- Allow: Safe operations ---
test_hook '{"tool_input":{"command":"rm -rf /tmp/junk"}}' 0 "Allow rm -rf /tmp/junk"
test_hook '{"tool_input":{"command":"rm node_modules"}}' 0 "Allow rm node_modules"
test_hook '{"tool_input":{"command":"rm /home/user/project/dist/bundle.js"}}' 0 "Allow rm specific file in project"
test_hook '{"tool_input":{"command":"ls /etc/hosts"}}' 0 "Allow read-only access to /etc"
test_hook '{"tool_input":{"command":"cat /usr/local/bin/script"}}' 0 "Allow cat on /usr"
test_hook '{"tool_input":{"command":"mv /tmp/a.txt /tmp/b.txt"}}' 0 "Allow mv in /tmp"
test_hook '{"tool_input":{"command":"chmod 644 myfile.txt"}}' 0 "Allow chmod on project file"

# --- Allow: Empty/missing input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_input":{}}' 0 "Allow missing command"
test_hook '{"tool_input":{"command":""}}' 0 "Allow empty command"

# --- Allow: Non-destructive system commands ---
test_hook '{"tool_input":{"command":"grep -r pattern /etc/nginx/"}}' 0 "Allow grep in /etc"
test_hook '{"tool_input":{"command":"find /usr -name \"*.so\""}}' 0 "Allow find in /usr (no delete)"
test_hook '{"tool_input":{"command":"cp /etc/hosts /tmp/"}}' 0 "Allow cp from /etc"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
