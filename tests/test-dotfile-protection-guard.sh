#!/bin/bash
# Tests for dotfile-protection-guard.sh
# Run: bash tests/test-dotfile-protection-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/dotfile-protection-guard.sh"

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

echo "dotfile-protection-guard.sh tests"
echo ""

# --- Block: Shell config files ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.bashrc\"}}" 2 "Block Write to .bashrc"
test_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.zshrc\"}}" 2 "Block Edit to .zshrc"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.bash_profile\"}}" 2 "Block Write to .bash_profile"
test_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.profile\"}}" 2 "Block Edit to .profile"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.zshenv\"}}" 2 "Block Write to .zshenv"

# --- Block: SSH ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/id_rsa\"}}" 2 "Block Write to .ssh/id_rsa"
test_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/config\"}}" 2 "Block Edit to .ssh/config"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.ssh/authorized_keys\"}}" 2 "Block Write to .ssh/authorized_keys"

# --- Block: Git credentials ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.git-credentials\"}}" 2 "Block Write to .git-credentials"
test_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.gitconfig\"}}" 2 "Block Edit to .gitconfig"

# --- Block: Other credentials ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.npmrc\"}}" 2 "Block Write to .npmrc"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.aws/credentials\"}}" 2 "Block Write to .aws/credentials"
test_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.config/gh/hosts.yml\"}}" 2 "Block Edit to gh hosts.yml"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.netrc\"}}" 2 "Block Write to .netrc"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.docker/config.json\"}}" 2 "Block Write to docker config"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.kube/config\"}}" 2 "Block Write to kube config"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.gnupg/trustdb.gpg\"}}" 2 "Block Write to gnupg"

# --- Allow: Claude Code config ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\"}}" 0 "Allow Write to .claude/settings.json"
test_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$HOME/.claude/CLAUDE.md\"}}" 0 "Allow Edit to .claude/CLAUDE.md"

# --- Allow: Project files ---
test_hook '{"tool_name":"Write","tool_input":{"file_path":"/home/user/project/src/main.py"}}' 0 "Allow Write to project file"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"./README.md"}}' 0 "Allow Edit to relative path"

# --- Allow: Empty input ---
test_hook '{}' 0 "Allow empty input"
test_hook '{"tool_name":"Write","tool_input":{}}' 0 "Allow missing file_path"

# --- Block: Tilde expansion ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"~/.bashrc\"}}" 2 "Block Write to ~/.bashrc (tilde)"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
