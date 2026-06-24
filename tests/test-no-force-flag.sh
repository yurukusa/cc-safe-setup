#!/bin/bash
# Tests for no-force-flag.sh
# Run: bash tests/test-no-force-flag.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/no-force-flag.sh"
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

echo "Testing no-force-flag.sh"
echo "========================"

# --- BLOCK: git push --force (long form) ---
run_test "git push --force blocks"            2 '"git push --force"'
run_test "git push origin main --force blocks" 2 '"git push origin main --force"'

# --- BLOCK: git push -f (short form — previously bypassed entirely) ---
run_test "git push -f blocks"                 2 '"git push -f"'
run_test "git push origin main -f blocks"     2 '"git push origin main -f"'
run_test "git push -f origin feature blocks"  2 '"git push -f origin feature"'

# --- ALLOW: --force-with-lease and non-force pushes (no false positives) ---
run_test "git push --force-with-lease allows" 0 '"git push --force-with-lease"'
run_test "git push allows"                    0 '"git push"'
run_test "git push origin main allows"        0 '"git push origin main"'
run_test "git push to branch ending in -f allows" 0 '"git push origin feature-f"'

# --- BLOCK: npm install --force / docker prune -f (other patterns, unchanged) ---
run_test "npm install --force blocks"         2 '"npm install --force"'
run_test "docker system prune -f blocks"      2 '"docker system prune -f"'

echo
echo "========================"
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
