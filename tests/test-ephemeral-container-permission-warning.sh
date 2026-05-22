#!/bin/bash
# Tests for ephemeral-container-permission-warning.sh
#
# Verifies the SessionStart hook behavior for issue #61141:
#   - No container signal → silent
#   - Container signal but settings is old → silent (likely a persistent
#     environment that has settings from a previous run)
#   - Container signal + settings missing → warning
#   - Container signal + settings created recently → warning
#   - Disable flag respected
#   - Custom settings path supported

set -uo pipefail

HOOK="$(dirname "$0")/../examples/ephemeral-container-permission-warning.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

TEST_ROOT=$(mktemp -d)
trap "rm -rf $TEST_ROOT" EXIT

# Helper to set up a fake HOME with controlled settings.json state
run_with_env() {
    local home="$1"
    local settings_path="$2"
    local extra_env="$3"

    mkdir -p "$home/.claude"
    # Run the hook with custom HOME + settings path
    HOME="$home" CC_EPHEMERAL_SETTINGS_PATH="$settings_path" eval "$extra_env bash \"$HOOK\"" 2>&1
}

echo "=== ephemeral-container-permission-warning.sh tests ==="

# --- Test 1: no container signal → silent ---
H1="$TEST_ROOT/host1"
mkdir -p "$H1/.claude"
# Make settings.json look old (1 hour ago) to neutralize fresh-settings signal
touch -d '1 hour ago' "$H1/.claude/settings.json"
# Unset all container env vars
output=$(env -i HOME="$H1" PATH="$PATH" CC_EPHEMERAL_SETTINGS_PATH="$H1/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no container signal → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 2: $CONTAINER set + settings missing → warning ---
H2="$TEST_ROOT/host2"
mkdir -p "$H2/.claude"
# settings.json missing
output=$(env -i HOME="$H2" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="$H2/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "EPHEMERAL-CONTAINER PERMISSION PERSISTENCE WARNING"; then
    assert_pass "\$CONTAINER set + missing settings → warning"
else
    assert_fail "expected warning, got rc=$rc output=$output"
fi

# --- Test 3: $CONTAINER set + settings is OLD → silent ---
H3="$TEST_ROOT/host3"
mkdir -p "$H3/.claude"
touch -d '1 hour ago' "$H3/.claude/settings.json"
output=$(env -i HOME="$H3" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="$H3/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "container signal + old settings → silent (likely persistent)"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 4: $CONTAINER set + settings created just now → warning ---
H4="$TEST_ROOT/host4"
mkdir -p "$H4/.claude"
touch "$H4/.claude/settings.json"  # just now
output=$(env -i HOME="$H4" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="$H4/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "EPHEMERAL-CONTAINER"; then
    assert_pass "container signal + fresh settings → warning"
else
    assert_fail "expected warning, got rc=$rc output=$output"
fi

# --- Test 5: $KUBERNETES_SERVICE_HOST set + settings missing → warning ---
H5="$TEST_ROOT/host5"
mkdir -p "$H5/.claude"
output=$(env -i HOME="$H5" PATH="$PATH" KUBERNETES_SERVICE_HOST="10.0.0.1" CC_EPHEMERAL_SETTINGS_PATH="$H5/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "KUBERNETES_SERVICE_HOST"; then
    assert_pass "Kubernetes signal → warning includes K8s reference"
else
    assert_fail "expected K8s warning, got rc=$rc output=$output"
fi

# --- Test 6: $CODESPACES set + settings missing → warning ---
H6="$TEST_ROOT/host6"
mkdir -p "$H6/.claude"
output=$(env -i HOME="$H6" PATH="$PATH" CODESPACES="true" CC_EPHEMERAL_SETTINGS_PATH="$H6/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "CODESPACES"; then
    assert_pass "Codespaces signal → warning"
else
    assert_fail "expected Codespaces warning, got rc=$rc output=$output"
fi

# --- Test 7: disable flag respected ---
H7="$TEST_ROOT/host7"
mkdir -p "$H7/.claude"
output=$(env -i HOME="$H7" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_WARN_DISABLE=1 CC_EPHEMERAL_SETTINGS_PATH="$H7/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag → silent"
else
    assert_fail "expected disabled, got rc=$rc output=$output"
fi

# --- Test 8: configurable fresh threshold ---
H8="$TEST_ROOT/host8"
mkdir -p "$H8/.claude"
touch -d '5 minutes ago' "$H8/.claude/settings.json"
# With default 60s threshold, 5min old is NOT fresh → silent
output=$(env -i HOME="$H8" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="$H8/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "5min-old settings + default threshold → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# Now with raised threshold to 600s, 5min should be flagged as fresh
output=$(env -i HOME="$H8" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_FRESH_THRESHOLD=600 CC_EPHEMERAL_SETTINGS_PATH="$H8/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "EPHEMERAL-CONTAINER"; then
    assert_pass "raised threshold → fresh signal fires"
else
    assert_fail "expected warning with raised threshold, got rc=$rc output=$output"
fi

# --- Test 9: warning references issue #61141 ---
H9="$TEST_ROOT/host9"
mkdir -p "$H9/.claude"
output=$(env -i HOME="$H9" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="$H9/.claude/settings.json" bash "$HOOK" 2>&1)
if echo "$output" | grep -q "claude-code#61141"; then
    assert_pass "warning references issue #61141"
else
    assert_fail "missing issue ref"
fi

# --- Test 10: warning includes BAKE INTO IMAGE recommendation ---
if echo "$output" | grep -q "BAKE INTO IMAGE"; then
    assert_pass "warning includes BAKE INTO IMAGE recommendation"
else
    assert_fail "missing BAKE recommendation"
fi

# --- Test 11: warning includes MOUNT PERSISTENT VOLUME recommendation ---
if echo "$output" | grep -q "MOUNT PERSISTENT VOLUME"; then
    assert_pass "warning includes MOUNT PERSISTENT VOLUME recommendation"
else
    assert_fail "missing MOUNT recommendation"
fi

# --- Test 12: warning includes PRE-STAGE recommendation ---
if echo "$output" | grep -q "PRE-STAGE PER RUN"; then
    assert_pass "warning includes PRE-STAGE PER RUN recommendation"
else
    assert_fail "missing PRE-STAGE recommendation"
fi

# --- Test 13: warning explains what does NOT help ---
if echo "$output" | grep -q "What does NOT help"; then
    assert_pass "warning explains what does NOT help"
else
    assert_fail "missing What-does-not-help section"
fi

# --- Test 14: hook exits 0 (non-blocking) ---
if [ "$rc" -eq 0 ]; then
    assert_pass "hook exits 0 (non-blocking)"
else
    assert_fail "hook returned non-zero rc=$rc"
fi

# --- Test 15: container signal but no settings.json reads as missing (warning) ---
H15="$TEST_ROOT/host15"
mkdir -p "$H15/.claude"
# settings.json deliberately not created
output=$(env -i HOME="$H15" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="$H15/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "missing"; then
    assert_pass "missing settings file → warning says 'missing'"
else
    assert_fail "expected 'missing' in output, got $output"
fi

# --- Test 16: no container, settings missing → still silent (need both) ---
H16="$TEST_ROOT/host16"
mkdir -p "$H16/.claude"
output=$(env -i HOME="$H16" PATH="$PATH" CC_EPHEMERAL_SETTINGS_PATH="$H16/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no container + missing settings → silent (need both signals)"
else
    assert_fail "expected silent without container, got rc=$rc output=$output"
fi

# --- Test 17: home directory printed in warning ---
output=$(env -i HOME="/tmp/special-home" PATH="$PATH" CONTAINER="docker" CC_EPHEMERAL_SETTINGS_PATH="/tmp/special-home/.claude/settings.json" bash "$HOOK" 2>&1)
rc=$?
if echo "$output" | grep -q "/tmp/special-home"; then
    assert_pass "home directory printed in warning"
else
    assert_fail "missing home dir, got $output"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
