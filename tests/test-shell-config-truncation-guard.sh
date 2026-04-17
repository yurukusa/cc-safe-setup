#!/bin/bash
# Tests for shell-config-truncation-guard.sh
# Run: bash tests/test-shell-config-truncation-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/shell-config-truncation-guard.sh"

# Create temp dir for test files
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create a fake home with shell config files
export HOME="$TEST_DIR"
echo '# My bash profile
export PATH="$HOME/bin:$PATH"
export EDITOR=vim
alias ll="ls -la"
eval "$(pyenv init -)"
source ~/.bash_completion
' > "$TEST_DIR/.bash_profile"

echo '# My zshrc
export PATH="$HOME/bin:$PATH"
autoload -Uz compinit
compinit
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
' > "$TEST_DIR/.zshrc"

echo '# My bashrc
if [ -f /etc/bashrc ]; then . /etc/bashrc; fi
export PATH="$HOME/bin:$PATH"
' > "$TEST_DIR/.bashrc"

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

echo "shell-config-truncation-guard.sh tests"
echo ""

# --- Block: Write tool truncating to empty ---
echo "= Write tool: truncation blocking ="
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.bash_profile\",\"content\":\"\"}}" 2 "Block empty Write to .bash_profile"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.zshrc\",\"content\":\"\"}}" 2 "Block empty Write to .zshrc"
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.bashrc\",\"content\":\"\"}}" 2 "Block empty Write to .bashrc"

# --- Block: Write tool with near-empty content ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.bash_profile\",\"content\":\"#\n\"}}" 2 "Block near-empty Write to .bash_profile"

# --- Block: Write tool with >60% size reduction ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.bash_profile\",\"content\":\"export PATH\"}}" 2 "Block >60% reduction of .bash_profile"

# --- Allow: Write tool with reasonable content ---
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.bash_profile\",\"content\":\"# Updated bash profile\nexport PATH=\\\"$TEST_DIR/bin:\$PATH\\\"\nexport EDITOR=vim\nalias ll=\\\"ls -la\\\"\neval \\\"\$(pyenv init -)\\\"\nsource ~/.bash_completion\n# Added new alias\nalias gs=\\\"git status\\\"\n\"}}" 0 "Allow reasonable Write to .bash_profile"

# --- Allow: Write to unprotected files ---
test_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.txt","content":""}}' 0 "Allow empty Write to unprotected file"
test_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/config.sh","content":"echo hello"}}' 0 "Allow Write to unprotected config"

# --- Block: Bash truncation commands ---
echo ""
echo "= Bash tool: truncation blocking ="
test_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"> $TEST_DIR/.bashrc\"}}" 2 "Block > redirect truncation of .bashrc"
test_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"truncate -s 0 $TEST_DIR/.zshrc\"}}" 2 "Block truncate command on .zshrc"
test_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\": > $TEST_DIR/.bash_profile\"}}" 2 "Block : > truncation of .bash_profile"

# --- Allow: Bash reading shell config ---
test_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat $TEST_DIR/.bashrc\"}}" 0 "Allow cat .bashrc"
test_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep PATH $TEST_DIR/.zshrc\"}}" 0 "Allow grep .zshrc"

# --- Allow: Bash with unrelated commands ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' 0 "Allow echo"
test_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' 0 "Allow ls"
test_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 0 "Allow git status"

# --- Allow: Non-matching tools ---
echo ""
echo "= Non-matching tools ="
test_hook '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' 0 "Allow Read tool"
test_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test"}}' 0 "Allow Edit tool"

# --- Edge cases ---
echo ""
echo "= Edge cases ="
test_hook '{}' 0 "Handle empty input"
test_hook '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "Handle empty command"

# Write to a file that doesn't exist yet (should allow)
test_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_DIR/.new_profile\",\"content\":\"\"}}" 0 "Allow Write to non-existent profile"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || exit 1
