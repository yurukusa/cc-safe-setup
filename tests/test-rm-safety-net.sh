#!/bin/bash
# Tests for rm-safety-net.sh
# Run: bash tests/test-rm-safety-net.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/rm-safety-net.sh"
PASS=0 FAIL=0

run_test() {
    local desc="$1" expected_exit="$2" cmd="$3"
    local actual_exit
    local input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":${cmd}}}"
    echo "$input" | bash "$HOOK" >/dev/null 2>/dev/null
    actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing rm-safety-net.sh"
echo "========================"

# --- BLOCK: rm on critical paths ---
run_test "rm -rf / blocks"                  2 '"rm -rf /"'
run_test "rm -rf ~ blocks"                  2 '"rm -rf ~"'
run_test "rm -rf /etc blocks"               2 '"rm -rf /etc"'
run_test "rm -rf /usr blocks"               2 '"rm -rf /usr"'
run_test "rm -rf /var blocks"               2 '"rm -rf /var"'
run_test "rm -rf /home blocks"              2 '"rm -rf /home"'
run_test "rm -rf .git blocks"               2 '"rm -rf .git"'
run_test "rm -rf .env blocks"               2 '"rm -rf .env"'
run_test "rm .env (non-recursive) blocks"   2 '"rm .env"'

# --- BLOCK: path traversal ---
run_test "rm -rf ../ blocks (path traversal)"      2 '"rm -rf ../"'
run_test "rm -rf ../foo blocks (path traversal)"   2 '"rm -rf ../foo"'

# --- BLOCK: sudo prefix variant ---
run_test "sudo rm -rf / blocks"             2 '"sudo rm -rf /"'

# --- ALLOW: safe build artifacts ---
run_test "rm -rf node_modules allows"       0 '"rm -rf node_modules"'
run_test "rm -rf dist allows"               0 '"rm -rf dist"'
run_test "rm -rf build allows"              0 '"rm -rf build"'
run_test "rm -rf __pycache__ allows"        0 '"rm -rf __pycache__"'
run_test "rm -rf .cache allows"             0 '"rm -rf .cache"'
run_test "rm -rf .pytest_cache allows"      0 '"rm -rf .pytest_cache"'
run_test "rm -rf coverage allows"           0 '"rm -rf coverage"'
run_test "rm -rf .next allows"              0 '"rm -rf .next"'

# --- ALLOW: relative paths under safe targets ---
run_test "rm -rf ./node_modules allows"     0 '"rm -rf ./node_modules"'
run_test "rm -rf ./dist allows"             0 '"rm -rf ./dist"'

# --- ALLOW: non-rm commands ---
run_test "ls -la passes through"            0 '"ls -la"'
run_test "echo hello passes through"        0 '"echo hello"'
run_test "git status passes through"        0 '"git status"'
run_test "cat README.md passes through"     0 '"cat README.md"'

# --- ALLOW: empty command ---
run_test "empty command passes through"     0 '""'

# --- find -delete handling (current dir allowed, sensitive paths blocked) ---
run_test "find . -delete allows (current dir is safe)"    0 '"find . -delete"'
run_test "find /home -delete blocks"                      2 '"find /home -delete"'
run_test "find /etc -delete blocks"                       2 '"find /etc -delete"'
run_test "find /tmp -delete allows (tmp is safe)"         0 '"find /tmp -delete"'
run_test "find node_modules -delete allows (safe target)" 0 '"find node_modules -delete"'

# --- BLOCK: shred (other destructive primitive) ---
run_test "shred secret.key blocks"          2 '"shred secret.key"'

echo
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
