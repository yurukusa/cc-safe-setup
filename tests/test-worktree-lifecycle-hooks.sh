set -euo pipefail
PASS=0
FAIL=0
test_hook() {
    local hook="$1" input="$2" expected_exit="$3" desc="$4"
    local actual_exit=0
    echo "$input" | bash "$hook" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}
HOOK_CREATE="$(dirname "$0")/../examples/worktree-create-log.sh"
HOOK_REMOVE="$(dirname "$0")/../examples/worktree-remove-uncommitted-guard.sh"
echo "=== worktree-create-log.sh ==="
test_hook "$HOOK_CREATE" '{"branch":"feature/test","path":"/tmp/wt-test"}' 0 "logs creation and passes"
test_hook "$HOOK_CREATE" '{}' 0 "empty input passes"
test_hook "$HOOK_CREATE" '' 0 "blank input passes"
echo ""
echo "=== worktree-remove-uncommitted-guard.sh ==="
test_hook "$HOOK_REMOVE" '{"path":"/nonexistent/path"}' 0 "nonexistent path passes"
test_hook "$HOOK_REMOVE" '{}' 0 "empty input passes"
test_hook "$HOOK_REMOVE" '' 0 "blank input passes"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
