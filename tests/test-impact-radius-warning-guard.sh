#!/bin/bash
# test-impact-radius-warning-guard.sh — Tests for impact-radius-warning-guard.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../examples/impact-radius-warning-guard.sh"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local input="$2"
    local expected_exit="$3"
    local expected_warn_substr="$4"
    local setup="$5"

    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    unset IRWG_BLOCK IRWG_QUIET IRWG_THRESHOLD

    if [ -n "$setup" ]; then
        eval "$setup"
    fi

    actual_exit=0
    HOOK_STDERR=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null) || actual_exit=$?

    cd /
    rm -rf "$TEST_DIR"

    # Check exit
    if [ "$actual_exit" != "$expected_exit" ]; then
        echo "FAIL: $name (expected exit $expected_exit, got $actual_exit)"
        [ -n "$HOOK_STDERR" ] && echo "  STDERR: $HOOK_STDERR"
        FAIL=$((FAIL + 1))
        return
    fi

    # Check warning substring (if specified)
    if [ -n "$expected_warn_substr" ]; then
        if echo "$HOOK_STDERR" | grep -qF "$expected_warn_substr"; then
            echo "PASS: $name"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (warning '$expected_warn_substr' not found)"
            echo "  STDERR: $HOOK_STDERR"
            FAIL=$((FAIL + 1))
        fi
    else
        # No warning expected
        if [ -z "$HOOK_STDERR" ]; then
            echo "PASS: $name"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $name (unexpected warning)"
            echo "  STDERR: $HOOK_STDERR"
            FAIL=$((FAIL + 1))
        fi
    fi
}

# Test 1: Empty command
run_test "empty command = silent" \
    '{"tool_input":{"command":""}}' \
    0 ""

# Test 2: ls command - no warning
run_test "ls command = silent" \
    '{"tool_input":{"command":"ls -la"}}' \
    0 ""

# Test 3: rm -rf with small dir (no warning)
run_test "rm -rf small dir = silent" \
    '{"tool_input":{"command":"rm -rf smalldir"}}' \
    0 "" \
    "mkdir smalldir && touch smalldir/a smalldir/b smalldir/c"

# Test 4: rm -rf with large dir (warning)
run_test "rm -rf 150 files = warn" \
    '{"tool_input":{"command":"rm -rf largedir"}}' \
    0 "150 files" \
    "mkdir largedir && for i in \$(seq 1 150); do touch largedir/f\$i; done"

# Test 5: rm -rf nonexistent path (no warning)
run_test "rm -rf nonexistent = silent" \
    '{"tool_input":{"command":"rm -rf nope"}}' \
    0 ""

# Test 6: git reset --hard HEAD~3 (no warning - below threshold)
run_test "git reset HEAD~3 = silent" \
    '{"tool_input":{"command":"git reset --hard HEAD~3"}}' \
    0 ""

# Test 7: git reset --hard HEAD~10 (warning)
run_test "git reset HEAD~10 = warn" \
    '{"tool_input":{"command":"git reset --hard HEAD~10"}}' \
    0 "10 commits"

# Test 8: SQL DELETE without WHERE = warn
run_test "DELETE FROM users without WHERE = warn" \
    '{"tool_input":{"command":"psql -c \"DELETE FROM users;\""}}' \
    0 "DELETE FROM without WHERE"

# Test 9: SQL DELETE with WHERE = silent
run_test "DELETE with WHERE = silent" \
    '{"tool_input":{"command":"psql -c \"DELETE FROM users WHERE id = 5\""}}' \
    0 ""

# Test 10: find -delete with large target = warn
run_test "find -delete 200 files = warn" \
    '{"tool_input":{"command":"find bigdir -type f -delete"}}' \
    0 "find -delete" \
    "mkdir bigdir && for i in \$(seq 1 200); do touch bigdir/f\$i; done"

# Test 11: kubectl delete --all = warn
run_test "kubectl delete --all = warn" \
    '{"tool_input":{"command":"kubectl delete pods --all -n production"}}' \
    0 "kubectl delete with --all"

# Test 12: kubectl delete -A = warn
run_test "kubectl delete -A = warn" \
    '{"tool_input":{"command":"kubectl delete configmap myconfig -A"}}' \
    0 "kubectl delete with --all or -A"

# Test 13: kubectl delete single = silent
run_test "kubectl delete specific = silent" \
    '{"tool_input":{"command":"kubectl delete pod my-pod -n default"}}' \
    0 ""

# Test 14: IRWG_BLOCK=1 + DELETE without WHERE = exit 2
run_test "DELETE without WHERE + IRWG_BLOCK = block" \
    '{"tool_input":{"command":"psql -c \"DELETE FROM users;\""}}' \
    2 "DELETE FROM without WHERE" \
    "export IRWG_BLOCK=1"

# Test 15: IRWG_THRESHOLD=10 + rm -rf with 15 files = warn
run_test "lower threshold = more warnings" \
    '{"tool_input":{"command":"rm -rf mediumdir"}}' \
    0 "15 files" \
    "mkdir mediumdir && for i in \$(seq 1 15); do touch mediumdir/f\$i; done && export IRWG_THRESHOLD=10"

# Test 16: git reset HEAD~5 = warn (exactly at threshold)
run_test "git reset HEAD~5 = warn at threshold" \
    '{"tool_input":{"command":"git reset --hard HEAD~5"}}' \
    0 "5 commits"

# Test 17: git reset --hard <commit-hash> = silent (no number)
run_test "git reset commit-hash = silent" \
    '{"tool_input":{"command":"git reset --hard abc1234"}}' \
    0 ""

# Test 18: rm with small flags (no -r) = silent
run_test "rm -f single file = silent" \
    '{"tool_input":{"command":"rm -f one.txt"}}' \
    0 ""

# Test 19: find without -delete = silent
run_test "find without -delete = silent" \
    '{"tool_input":{"command":"find /tmp -type f"}}' \
    0 ""

# Test 20: docker volume prune (no docker installed in test env = silent)
run_test "docker volume rm = handled gracefully" \
    '{"tool_input":{"command":"docker volume prune -f"}}' \
    0 ""

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
