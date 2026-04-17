#!/bin/bash
# Tests for dangerous-pip-flag-guard.sh
# Run: bash tests/test-dangerous-pip-flag-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/dangerous-pip-flag-guard.sh"

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

echo "dangerous-pip-flag-guard.sh tests"
echo ""

# --- Block: --break-system-packages ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install --break-system-packages requests"}}' 2 "Block --break-system-packages"
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip3 install --break-system-packages numpy"}}' 2 "Block pip3 --break-system-packages"
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install requests --break-system-packages"}}' 2 "Block flag after package name"

# --- Block: sudo pip install ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"sudo pip install flask"}}' 2 "Block sudo pip install"
test_hook '{"tool_name":"Bash","tool_input":{"command":"sudo pip3 install django"}}' 2 "Block sudo pip3 install"

# --- Block: targeting system directories ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install --target=/usr/lib/python3/dist-packages requests"}}' 2 "Block install to /usr/lib"
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install --target /opt/python/lib requests"}}' 2 "Block install to /opt"

# --- Allow: normal pip install ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}' 0 "Allow normal pip install"
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install --user requests"}}' 0 "Allow --user install"
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip install -r requirements.txt"}}' 0 "Allow requirements.txt"
test_hook '{"tool_name":"Bash","tool_input":{"command":"pip3 install flask==2.0"}}' 0 "Allow versioned install"

# --- Allow: non-pip commands ---
test_hook '{"tool_name":"Bash","tool_input":{"command":"npm install express"}}' 0 "Allow npm install"
test_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}' 0 "Allow git status"
test_hook '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' 0 "Allow echo"

# --- Allow: empty/missing ---
test_hook '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "Allow empty command"
test_hook '{"tool_name":"Bash","tool_input":{}}' 0 "Allow no command"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || exit 1
