#!/bin/bash
# test-multi-window-auth-drift-detector.sh — Tests for multi-window-auth-drift-detector.sh

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/examples/multi-window-auth-drift-detector.sh"

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
export CC_AUTH_DRIFT_STATE_DIR="$STATE_DIR"

# Helper: create a credentials file with mtime set to N seconds ago
make_cred_with_mtime() {
    local seconds_ago="$1"
    local f
    f=$(mktemp)
    echo '{"access_token":"x"}' > "$f"
    local target_ts=$(( $(date +%s) - seconds_ago ))
    if touch -d "@${target_ts}" "$f" 2>/dev/null; then
        :
    else
        # macOS fallback: touch -t YYYYMMDDhhmm.SS
        local stamp
        stamp=$(date -r "$target_ts" "+%Y%m%d%H%M.%S")
        touch -t "$stamp" "$f"
    fi
    echo "$f"
}

# Test 1: Disable switch
CRED1=$(make_cred_with_mtime 0)
run_test "disable switch silences hook" \
    "0" "" \
    env CC_AUTH_DRIFT_DISABLE=1 \
        CC_AUTH_DRIFT_CRED_FILE="$CRED1" \
        CC_AUTH_DRIFT_SESSION_ID=test1 \
        bash "$HOOK"

# Test 2: Quiet mode — processes but emits nothing
CRED2=$(make_cred_with_mtime 0)
# Session started 60 seconds ago, cred file now == drift detected
SESSION_START_T2=$(( $(date +%s) - 60 ))
run_test "quiet mode emits nothing" \
    "0" "" \
    env CC_AUTH_DRIFT_QUIET=1 \
        CC_AUTH_DRIFT_CRED_FILE="$CRED2" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T2" \
        CC_AUTH_DRIFT_SESSION_ID=test2 \
        bash "$HOOK"

# Test 3: No credentials file exists — exits silently
run_test "no cred file exits silently" \
    "0" "" \
    env CC_AUTH_DRIFT_CRED_FILE="/nonexistent/path/cred.json" \
        CC_AUTH_DRIFT_SESSION_ID=test3 \
        bash "$HOOK"

# Test 4: Cred mtime older than session start — no advisory
CRED4=$(make_cred_with_mtime 3600)  # 1 hour ago
SESSION_START_T4=$(( $(date +%s) - 60 ))  # 60s ago
run_test "cred mtime older than session start emits nothing" \
    "0" "" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED4" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T4" \
        CC_AUTH_DRIFT_SESSION_ID=test4 \
        bash "$HOOK"

# Test 5: Cred mtime newer than session start — emits advisory
CRED5=$(make_cred_with_mtime 0)
SESSION_START_T5=$(( $(date +%s) - 60 ))
run_test "cred mtime newer than session start emits advisory" \
    "0" "Cluster 19 axis 19E" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED5" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T5" \
        CC_AUTH_DRIFT_SESSION_ID=test5 \
        bash "$HOOK"

# Test 6: Advisory references anchor case #62790
CRED6=$(make_cred_with_mtime 0)
SESSION_START_T6=$(( $(date +%s) - 60 ))
run_test "advisory references #62790" \
    "0" "62790" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED6" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T6" \
        CC_AUTH_DRIFT_SESSION_ID=test6 \
        bash "$HOOK"

# Test 7: Advisory references /account recovery
CRED7=$(make_cred_with_mtime 0)
SESSION_START_T7=$(( $(date +%s) - 60 ))
run_test "advisory references /account" \
    "0" "/account" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED7" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T7" \
        CC_AUTH_DRIFT_SESSION_ID=test7 \
        bash "$HOOK"

# Test 8: One-shot — second invocation does not re-fire
CRED8=$(make_cred_with_mtime 0)
SESSION_START_T8=$(( $(date +%s) - 60 ))
env CC_AUTH_DRIFT_CRED_FILE="$CRED8" \
    CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T8" \
    CC_AUTH_DRIFT_SESSION_ID=test8 \
    bash "$HOOK" 2>/dev/null
run_test "second invocation does not re-fire" \
    "0" "" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED8" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T8" \
        CC_AUTH_DRIFT_SESSION_ID=test8 \
        bash "$HOOK"

# Test 9: Different sessions have independent guard
CRED9=$(make_cred_with_mtime 0)
SESSION_START_T9=$(( $(date +%s) - 60 ))
run_test "different session id fires independently" \
    "0" "Cluster 19 axis 19E" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED9" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T9" \
        CC_AUTH_DRIFT_SESSION_ID=test9 \
        bash "$HOOK"

# Test 10: First fire records session start, no advisory
CRED10=$(make_cred_with_mtime 3600)
# No SESSION_START supplied. First fire just records, no advisory.
run_test "first fire records start, no advisory" \
    "0" "" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED10" \
        CC_AUTH_DRIFT_SESSION_ID=test10 \
        bash "$HOOK"
# Verify start file was created
if [[ -f "$STATE_DIR/auth-drift-test10.start" ]]; then
    echo "✓ first fire created start file"
    PASS=$((PASS + 1))
else
    echo "✗ first fire created start file"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("first fire created start file")
fi

# Test 11: Quiet mode still marks guard
CRED11=$(make_cred_with_mtime 0)
SESSION_START_T11=$(( $(date +%s) - 60 ))
env CC_AUTH_DRIFT_QUIET=1 \
    CC_AUTH_DRIFT_CRED_FILE="$CRED11" \
    CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T11" \
    CC_AUTH_DRIFT_SESSION_ID=test11 \
    bash "$HOOK"
# Second fire (non-quiet) should not emit since guard was marked
run_test "quiet mode marks guard so non-quiet later does not fire" \
    "0" "" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED11" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T11" \
        CC_AUTH_DRIFT_SESSION_ID=test11 \
        bash "$HOOK"

# Test 12: Advisory mentions multi-window pattern
CRED12=$(make_cred_with_mtime 0)
SESSION_START_T12=$(( $(date +%s) - 60 ))
run_test "advisory mentions multi-window" \
    "0" "multi-window" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED12" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T12" \
        CC_AUTH_DRIFT_SESSION_ID=test12 \
        bash "$HOOK"

# Test 13: Advisory mentions field guide URL
CRED13=$(make_cred_with_mtime 0)
SESSION_START_T13=$(( $(date +%s) - 60 ))
run_test "advisory references field guide" \
    "0" "gist.github.com" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED13" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T13" \
        CC_AUTH_DRIFT_SESSION_ID=test13 \
        bash "$HOOK"

# Test 14: Advisory mentions disable env var
CRED14=$(make_cred_with_mtime 0)
SESSION_START_T14=$(( $(date +%s) - 60 ))
run_test "advisory mentions CC_AUTH_DRIFT_DISABLE" \
    "0" "CC_AUTH_DRIFT_DISABLE" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED14" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T14" \
        CC_AUTH_DRIFT_SESSION_ID=test14 \
        bash "$HOOK"

# Test 15: Empty cred file path treated as no cred file
run_test "empty cred path no advisory" \
    "0" "" \
    env CC_AUTH_DRIFT_CRED_FILE="" \
        CC_AUTH_DRIFT_SESSION_ID=test15 \
        bash "$HOOK"

# Test 16: Gap displayed in advisory
CRED16=$(make_cred_with_mtime 0)
SESSION_START_T16=$(( $(date +%s) - 120 ))
run_test "gap displayed in advisory" \
    "0" "after this session started" \
    env CC_AUTH_DRIFT_CRED_FILE="$CRED16" \
        CC_AUTH_DRIFT_SESSION_START="$SESSION_START_T16" \
        CC_AUTH_DRIFT_SESSION_ID=test16 \
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
