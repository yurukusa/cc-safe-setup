set -euo pipefail
PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/pr-duplicate-guard.sh"
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
echo "=== pr-duplicate-guard.sh ==="
test_hook '{"tool_input":{"command":"git push origin main"}}' 0 "git push passes through"
test_hook '{"tool_input":{"command":"npm publish"}}' 0 "npm publish passes through"
test_hook '{"tool_input":{"command":"echo hello"}}' 0 "echo passes through"
test_hook '{"tool_input":{"command":"gh pr list"}}' 0 "gh pr list passes through"
test_hook '{"tool_input":{"command":"gh pr view 123"}}' 0 "gh pr view passes through"
test_hook '{"tool_input":{"command":"gh issue create --title test"}}' 0 "gh issue create passes through"
test_hook '{"tool_input":{"command":"gh pr create --title \"test\" --body \"test\""}}' 0 "gh pr create on unique branch passes"
test_hook '{}' 0 "empty input passes"
test_hook '' 0 "blank input passes"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
