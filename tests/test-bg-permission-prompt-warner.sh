#!/bin/bash
# test-bg-permission-prompt-warner.sh — Tests for bg-permission-prompt-warner.sh

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/examples/bg-permission-prompt-warner.sh"

PASS=0
FAIL=0
FAILED_TESTS=()

run_test() {
    local name="$1"
    local expected_exit="$2"
    local expected_pattern="$3"
    shift 3
    local stderr_file
    stderr_file=$(mktemp)
    local actual_exit
    "$@" 2>"$stderr_file"
    actual_exit=$?
    local stderr_content
    stderr_content=$(cat "$stderr_file")
    rm -f "$stderr_file"

    local exit_ok=false
    if [[ "$actual_exit" == "$expected_exit" ]]; then
        exit_ok=true
    fi

    local pattern_ok=false
    if [[ -z "$expected_pattern" ]]; then
        if [[ -z "$stderr_content" ]]; then
            pattern_ok=true
        fi
    elif [[ "$expected_pattern" == "ANY" ]]; then
        pattern_ok=true
    else
        if echo "$stderr_content" | grep -q "$expected_pattern"; then
            pattern_ok=true
        fi
    fi

    if [[ "$exit_ok" == "true" && "$pattern_ok" == "true" ]]; then
        echo "✓ $name"
        PASS=$((PASS + 1))
    else
        echo "✗ $name (exit: $actual_exit/$expected_exit, pattern: ${expected_pattern})"
        if [[ -n "$stderr_content" ]]; then
            echo "  stderr: $(echo "$stderr_content" | head -3 | tr '\n' ' ')"
        fi
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
}

STATE_DIR=$(mktemp -d)
export CC_BG_WARN_STATE_DIR="$STATE_DIR"

# Test 1: Disable switch
run_test "disable switch silences hook" \
    "0" "" \
    env CC_BG_WARN_DISABLE=1 \
        CC_BG_WARN_FORCE=1 \
        CC_BG_WARN_SESSION_ID=test1 \
        bash "$HOOK"

# Test 2: Quiet mode emits nothing
run_test "quiet mode emits nothing" \
    "0" "" \
    env CC_BG_WARN_QUIET=1 \
        CC_BG_WARN_FORCE=1 \
        CC_BG_WARN_SESSION_ID=test2 \
        bash "$HOOK"

# Test 3: No parent cmd, no force — exits silently
run_test "no parent cmd no force exits silently" \
    "0" "" \
    env -u CC_BG_WARN_FORCE \
        CC_BG_WARN_PARENT_CMD="" \
        CC_BG_WARN_SESSION_ID=test3 \
        bash "$HOOK"

# Test 4: Parent cmd without --bg — exits silently
run_test "parent cmd without --bg exits silently" \
    "0" "" \
    env -u CC_BG_WARN_FORCE \
        CC_BG_WARN_PARENT_CMD="node /usr/local/bin/claude --print" \
        CC_BG_WARN_SESSION_ID=test4 \
        bash "$HOOK"

# Test 5: Parent cmd with --bg — emits advisory
run_test "parent cmd with --bg emits advisory" \
    "0" "Cluster 24 axis 24A" \
    env CC_BG_WARN_PARENT_CMD="node /usr/local/bin/claude --bg --model opus --name test" \
        CC_BG_WARN_SESSION_ID=test5 \
        bash "$HOOK"

# Test 6: Parent cmd with --background — emits advisory
run_test "parent cmd with --background emits advisory" \
    "0" "Cluster 24 axis 24A" \
    env CC_BG_WARN_PARENT_CMD="claude --background work" \
        CC_BG_WARN_SESSION_ID=test6 \
        bash "$HOOK"

# Test 7: Advisory references anchor #64271
run_test "advisory references #64271" \
    "0" "64271" \
    env CC_BG_WARN_PARENT_CMD="claude --bg work" \
        CC_BG_WARN_SESSION_ID=test7 \
        bash "$HOOK"

# Test 8: Advisory mentions acceptEdits
run_test "advisory mentions acceptEdits" \
    "0" "acceptEdits" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test8 \
        bash "$HOOK"

# Test 9: Advisory mentions the three sibling axes
run_test "advisory mentions 24B sibling axis" \
    "0" "24B" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test9 \
        bash "$HOOK"

run_test "advisory mentions 24C sibling axis" \
    "0" "24C" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test9c \
        bash "$HOOK"

run_test "advisory mentions 24D sibling axis" \
    "0" "24D" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test9d \
        bash "$HOOK"

# Test 10: One-shot per session — second invocation does not re-fire
env CC_BG_WARN_PARENT_CMD="claude --bg" \
    CC_BG_WARN_SESSION_ID=test10 \
    bash "$HOOK" 2>/dev/null
run_test "second invocation does not re-fire" \
    "0" "" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test10 \
        bash "$HOOK"

# Test 11: Force flag bypasses parent detection
run_test "FORCE flag emits without parent cmdline match" \
    "0" "Cluster 24 axis 24A" \
    env CC_BG_WARN_FORCE=1 \
        CC_BG_WARN_PARENT_CMD="" \
        CC_BG_WARN_SESSION_ID=test11 \
        bash "$HOOK"

# Test 12: Different session id fires independently
run_test "different session id fires independently" \
    "0" "Cluster 24 axis 24A" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test12 \
        bash "$HOOK"

# Test 13: Quiet mode still marks guard
env CC_BG_WARN_QUIET=1 \
    CC_BG_WARN_FORCE=1 \
    CC_BG_WARN_SESSION_ID=test13 \
    bash "$HOOK"
run_test "quiet mode marks guard so non-quiet later does not fire" \
    "0" "" \
    env CC_BG_WARN_FORCE=1 \
        CC_BG_WARN_SESSION_ID=test13 \
        bash "$HOOK"

# Test 14: Advisory references disable env var
run_test "advisory mentions CC_BG_WARN_DISABLE" \
    "0" "CC_BG_WARN_DISABLE" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test14 \
        bash "$HOOK"

# Test 15: Substring match in middle of cmdline
run_test "--bg in middle of cmdline matches" \
    "0" "Cluster 24 axis 24A" \
    env CC_BG_WARN_PARENT_CMD="env FOO=bar node claude --bg --model opus extra-args" \
        CC_BG_WARN_SESSION_ID=test15 \
        bash "$HOOK"

# Test 16: --bgwhatever should NOT match (word boundary)
run_test "--bgsomething does not falsely match" \
    "0" "" \
    env -u CC_BG_WARN_FORCE \
        CC_BG_WARN_PARENT_CMD="claude --bgsomething-suffix" \
        CC_BG_WARN_SESSION_ID=test16 \
        bash "$HOOK"

# Test 17: Advisory references workaround steps
run_test "advisory includes terminal-attached workaround" \
    "0" "terminal attached" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test17 \
        bash "$HOOK"

# Test 18: Advisory mentions audit tool-call distribution workaround
run_test "advisory mentions tool-call distribution audit" \
    "0" "tool-call distribution" \
    env CC_BG_WARN_PARENT_CMD="claude --bg" \
        CC_BG_WARN_SESSION_ID=test18 \
        bash "$HOOK"

# Cleanup
rm -rf "$STATE_DIR"

echo ""
echo "─────────────────────────────"
echo "Tests: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed: ${FAILED_TESTS[*]}"
    exit 1
fi
exit 0
