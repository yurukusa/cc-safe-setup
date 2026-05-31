#!/bin/bash
# test-auth-macos-sleep-detector.sh — Tests for auth-macos-sleep-detector.sh

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/examples/auth-macos-sleep-detector.sh"

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

# Set up isolated state dir
STATE_DIR=$(mktemp -d)
export CC_AUTH_MACOS_SLEEP_STATE_DIR="$STATE_DIR"

# Set up fake pmset that emits a wake event with a controlled timestamp
make_pmset_stub() {
    local wake_ago_seconds="$1"
    local stub
    stub=$(mktemp)
    local wake_ts
    # Use GNU date if available; macOS date otherwise
    if date -d "@0" >/dev/null 2>&1; then
        wake_ts=$(date -d "@$(( $(date +%s) - wake_ago_seconds ))" "+%Y-%m-%d %H:%M:%S")
    else
        wake_ts=$(date -r "$(( $(date +%s) - wake_ago_seconds ))" "+%Y-%m-%d %H:%M:%S")
    fi
    cat > "$stub" <<STUB
#!/bin/bash
if [[ "\$1" = "-g" && "\$2" = "log" ]]; then
    echo "$wake_ts +0900 Wake               Wake from Normal Sleep [DriverDesc]"
fi
STUB
    chmod +x "$stub"
    echo "$stub"
}

make_empty_pmset_stub() {
    local stub
    stub=$(mktemp)
    cat > "$stub" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$stub"
    echo "$stub"
}

# Test 1: Non-macOS OS — exits silently
run_test "non-macOS OS exits silently" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Linux \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test1 \
        bash "$HOOK"

# Test 2: Disable env var — exits silently even on Darwin
PMSET_FRESH=$(make_pmset_stub 60)
run_test "CC_AUTH_MACOS_SLEEP_DISABLE=1 exits silently" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_DISABLE=1 \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test2 \
        bash "$HOOK"

# Test 3: Quiet mode — no stderr but processes
PMSET_FRESH3=$(make_pmset_stub 60)
run_test "CC_AUTH_MACOS_SLEEP_QUIET=1 produces no stderr" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_QUIET=1 \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH3" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test3 \
        bash "$HOOK"

# Test 4: Recent wake within window — emits advisory
PMSET_FRESH4=$(make_pmset_stub 60)
run_test "recent wake (60s ago, 1800s window) emits advisory" \
    "0" "Cluster 19 axis 19B" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH4" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test4 \
        bash "$HOOK"

# Test 5: Stale wake outside window — exits silently
PMSET_STALE=$(make_pmset_stub 7200)
run_test "stale wake (7200s ago, 1800s window) exits silently" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_STALE" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test5 \
        bash "$HOOK"

# Test 6: Custom window includes wake — emits advisory
PMSET_CUSTOM=$(make_pmset_stub 3000)
run_test "custom window 3600s includes 3000s wake — emits" \
    "0" "Cluster 19 axis 19B" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_WINDOW=3600 \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_CUSTOM" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test6 \
        bash "$HOOK"

# Test 7: Empty pmset output — exits silently
PMSET_EMPTY=$(make_empty_pmset_stub)
run_test "empty pmset output exits silently" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_EMPTY" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test7 \
        bash "$HOOK"

# Test 8: One-shot guard — second invocation exits silently
PMSET_FRESH8=$(make_pmset_stub 60)
env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
    CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH8" \
    CC_AUTH_MACOS_SLEEP_SESSION_ID=test8 \
    bash "$HOOK" 2>/dev/null

run_test "one-shot guard prevents second emission" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH8" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test8 \
        bash "$HOOK"

# Test 9: Different session id — fires independently
PMSET_FRESH9=$(make_pmset_stub 120)
run_test "different session id fires independently" \
    "0" "Cluster 19 axis 19B" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH9" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test9 \
        bash "$HOOK"

# Test 10: Missing pmset binary — exits silently
run_test "missing pmset binary exits silently" \
    "0" "" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD=/nonexistent/pmset \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test10 \
        bash "$HOOK"

# Test 11: Advisory references the auth-status-checker companion
PMSET_FRESH11=$(make_pmset_stub 300)
run_test "advisory references auth-status-checker companion" \
    "0" "auth-status-checker" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH11" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test11 \
        bash "$HOOK"

# Test 12: Advisory references /login recovery
PMSET_FRESH12=$(make_pmset_stub 400)
run_test "advisory references /login recovery" \
    "0" "/login" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH12" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test12 \
        bash "$HOOK"

# Test 13: Advisory references anchor issue #59937
PMSET_FRESH13=$(make_pmset_stub 500)
run_test "advisory references anchor issue #59937" \
    "0" "59937" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH13" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test13 \
        bash "$HOOK"

# Test 14: Invalid window value falls back to default
PMSET_FRESH14=$(make_pmset_stub 120)
run_test "invalid window value falls back to default 1800" \
    "0" "Cluster 19 axis 19B" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_WINDOW=invalid \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_FRESH14" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test14 \
        bash "$HOOK"

# Test 15: WSL/Linux env without OS override — exits silently
run_test "no OS override on Linux exits silently" \
    "0" "" \
    env -u CC_AUTH_MACOS_SLEEP_FORCE_OS \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test15 \
        bash "$HOOK"

# Test 16: Zero-window edge case — only fires for current second
PMSET_ZERO=$(make_pmset_stub 0)
run_test "0s gap with 60s window fires advisory" \
    "0" "Cluster 19 axis 19B" \
    env CC_AUTH_MACOS_SLEEP_FORCE_OS=Darwin \
        CC_AUTH_MACOS_SLEEP_WINDOW=60 \
        CC_AUTH_MACOS_SLEEP_PMSET_CMD="$PMSET_ZERO" \
        CC_AUTH_MACOS_SLEEP_SESSION_ID=test16 \
        bash "$HOOK"

# Cleanup
rm -rf "$STATE_DIR"

# Summary
echo ""
echo "─────────────────────────────"
echo "Tests: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed: ${FAILED_TESTS[*]}"
    exit 1
fi
exit 0
