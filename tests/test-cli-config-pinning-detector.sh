#!/bin/bash
# test-cli-config-pinning-detector.sh — Tests for cli-config-pinning-detector.sh

set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/examples/cli-config-pinning-detector.sh"

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
export CC_AUTH_PIN_STATE_DIR="$STATE_DIR"

# Helper: write a config file with given content
make_config() {
    local content="$1"
    local f
    f=$(mktemp)
    echo "$content" > "$f"
    echo "$f"
}

# Test 1: Disable switch silences hook
CFG1=$(make_config '{"organization_id":"org_abc123","other":"x"}')
run_test "disable switch silences hook" \
    "0" "" \
    env CC_AUTH_PIN_DISABLE=1 \
        CC_AUTH_PIN_CONFIG="$CFG1" \
        CC_AUTH_PIN_SESSION_ID=test1 \
        bash "$HOOK"

# Test 2: Config file does not exist — exits silently
run_test "no config file exits silently" \
    "0" "" \
    env CC_AUTH_PIN_CONFIG="/nonexistent/path.json" \
        CC_AUTH_PIN_SESSION_ID=test2 \
        bash "$HOOK"

# Test 3: Config exists but no organization_id — exits silently
CFG3=$(make_config '{"api_key":"sk-x","email":"u@x.com"}')
run_test "no organization_id field exits silently" \
    "0" "" \
    env CC_AUTH_PIN_CONFIG="$CFG3" \
        CC_AUTH_PIN_SESSION_ID=test3 \
        bash "$HOOK"

# Test 4: Config with organization_id emits advisory
CFG4=$(make_config '{"organization_id":"org_abc123","email":"u@x.com"}')
run_test "config with organization_id emits advisory" \
    "0" "Cluster 19 axis 19H" \
    env CC_AUTH_PIN_CONFIG="$CFG4" \
        CC_AUTH_PIN_SESSION_ID=test4 \
        bash "$HOOK"

# Test 5: Advisory includes the pinned organization_id value
CFG5=$(make_config '{"organization_id":"org_xyz_test_value","email":"u@x.com"}')
run_test "advisory includes pinned org_id value" \
    "0" "org_xyz_test_value" \
    env CC_AUTH_PIN_CONFIG="$CFG5" \
        CC_AUTH_PIN_SESSION_ID=test5 \
        bash "$HOOK"

# Test 6: Advisory references anchor case #60742
CFG6=$(make_config '{"organization_id":"org_abc"}')
run_test "advisory references #60742" \
    "0" "60742" \
    env CC_AUTH_PIN_CONFIG="$CFG6" \
        CC_AUTH_PIN_SESSION_ID=test6 \
        bash "$HOOK"

# Test 7: Advisory recommends /account
CFG7=$(make_config '{"organization_id":"org_abc"}')
run_test "advisory recommends /account" \
    "0" "/account" \
    env CC_AUTH_PIN_CONFIG="$CFG7" \
        CC_AUTH_PIN_SESSION_ID=test7 \
        bash "$HOOK"

# Test 8: Quiet mode emits nothing but marks guard
CFG8=$(make_config '{"organization_id":"org_abc"}')
run_test "quiet mode emits nothing" \
    "0" "" \
    env CC_AUTH_PIN_QUIET=1 \
        CC_AUTH_PIN_CONFIG="$CFG8" \
        CC_AUTH_PIN_SESSION_ID=test8 \
        bash "$HOOK"
# Second fire (non-quiet) does not re-fire
run_test "quiet mode marks guard so non-quiet later does not fire" \
    "0" "" \
    env CC_AUTH_PIN_CONFIG="$CFG8" \
        CC_AUTH_PIN_SESSION_ID=test8 \
        bash "$HOOK"

# Test 9: One-shot — second invocation does not re-fire
CFG9=$(make_config '{"organization_id":"org_abc"}')
env CC_AUTH_PIN_CONFIG="$CFG9" \
    CC_AUTH_PIN_SESSION_ID=test9 \
    bash "$HOOK" 2>/dev/null
run_test "second invocation does not re-fire" \
    "0" "" \
    env CC_AUTH_PIN_CONFIG="$CFG9" \
        CC_AUTH_PIN_SESSION_ID=test9 \
        bash "$HOOK"

# Test 10: Different sessions fire independently
CFG10=$(make_config '{"organization_id":"org_abc"}')
run_test "different session id fires independently" \
    "0" "Cluster 19 axis 19H" \
    env CC_AUTH_PIN_CONFIG="$CFG10" \
        CC_AUTH_PIN_SESSION_ID=test10 \
        bash "$HOOK"

# Test 11: Advisory mentions field guide URL
CFG11=$(make_config '{"organization_id":"org_abc"}')
run_test "advisory references field guide" \
    "0" "gist.github.com" \
    env CC_AUTH_PIN_CONFIG="$CFG11" \
        CC_AUTH_PIN_SESSION_ID=test11 \
        bash "$HOOK"

# Test 12: Advisory mentions disable env var
CFG12=$(make_config '{"organization_id":"org_abc"}')
run_test "advisory mentions CC_AUTH_PIN_DISABLE" \
    "0" "CC_AUTH_PIN_DISABLE" \
    env CC_AUTH_PIN_CONFIG="$CFG12" \
        CC_AUTH_PIN_SESSION_ID=test12 \
        bash "$HOOK"

# Test 13: Organization_id with whitespace around colon
CFG13=$(make_config '{"organization_id" : "org_with_spaces"}')
run_test "whitespace around colon parsed correctly" \
    "0" "org_with_spaces" \
    env CC_AUTH_PIN_CONFIG="$CFG13" \
        CC_AUTH_PIN_SESSION_ID=test13 \
        bash "$HOOK"

# Test 14: Multi-line config file with organization_id
CFG14=$(mktemp)
cat > "$CFG14" <<JSON
{
  "email": "user@example.com",
  "organization_id": "org_multiline_value",
  "other": "x"
}
JSON
run_test "multi-line config parsed correctly" \
    "0" "org_multiline_value" \
    env CC_AUTH_PIN_CONFIG="$CFG14" \
        CC_AUTH_PIN_SESSION_ID=test14 \
        bash "$HOOK"

# Test 15: Null organization_id treated as no pin
CFG15=$(make_config '{"organization_id":null,"email":"u@x.com"}')
run_test "null org_id treated as no pin" \
    "0" "" \
    env CC_AUTH_PIN_CONFIG="$CFG15" \
        CC_AUTH_PIN_SESSION_ID=test15 \
        bash "$HOOK"

# Test 16: Advisory recommends editing the file
CFG16=$(make_config '{"organization_id":"org_abc"}')
run_test "advisory recommends editing config file" \
    "0" "Edit" \
    env CC_AUTH_PIN_CONFIG="$CFG16" \
        CC_AUTH_PIN_SESSION_ID=test16 \
        bash "$HOOK"

# Test 17: Advisory includes the config file path
CFG17=$(make_config '{"organization_id":"org_abc"}')
run_test "advisory includes config file path" \
    "0" "$(basename "$CFG17")" \
    env CC_AUTH_PIN_CONFIG="$CFG17" \
        CC_AUTH_PIN_SESSION_ID=test17 \
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
