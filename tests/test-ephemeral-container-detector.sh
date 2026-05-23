#!/bin/bash
# Tests for ephemeral-container-detector.sh
#
# Verifies the SessionStart hook behavior for issue #61141:
#   Layer 1 (container detected) AND Layer 2 (.claude/ looks recreated) →
#   warning. Either layer alone → silent.

set -uo pipefail

HOOK="$(dirname "$0")/../examples/ephemeral-container-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Each test runs the hook in a clean env. Container signals that the hook
# reads directly from the filesystem (/.dockerenv, /proc/1/cgroup) cannot be
# mocked here; tests rely on env-var signals (CONTAINER, DEVCONTAINER, etc.)
# which exercise the same code path.

TEST_ROOT=$(mktemp -d)
trap "rm -rf $TEST_ROOT" EXIT

# Sandbox a fake CLAUDE_HOME so we never touch the real ~/.claude
FAKE_HOME="$TEST_ROOT/claude-home"

# Wrapper: run hook with a clean env containing only what each test sets.
# Critically, the wrapper UNSETs the container env vars that may leak from the
# test harness itself (CI workers can set CONTAINER/CODESPACES).
run_hook() {
    env -i \
        HOME="$TEST_ROOT" \
        PATH="$PATH" \
        CC_CLAUDE_HOME="$FAKE_HOME" \
        HOSTNAME="testhost" \
        "$@" \
        bash "$HOOK" 2>&1
}

echo "=== ephemeral-container-detector.sh tests ==="

# --- Test 1: no container signals → silent ---
rm -rf "$FAKE_HOME"
output=$(run_hook)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no container signals → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 2: CONTAINER env but no reset signal (settings present, approvals present) → silent ---
mkdir -p "$FAKE_HOME"
cat > "$FAKE_HOME/settings.json" <<'JSON'
{
  "mcpServers": {"slack": {"command": "slack-mcp"}},
  "enabledMcpjsonServers": ["slack"]
}
JSON
output=$(run_hook CONTAINER=docker)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "container + approvals present → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 3: CONTAINER env + missing settings.json → warning ---
rm -rf "$FAKE_HOME"
output=$(run_hook CONTAINER=docker)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "MCP approval state may not persist"; then
    assert_pass "container + missing settings → warning"
else
    assert_fail "expected warning, got rc=$rc output=$output"
fi

# --- Test 4: warning references issue #61141 ---
if echo "$output" | grep -q "claude-code#61141"; then
    assert_pass "warning references issue #61141"
else
    assert_fail "missing issue ref, got $output"
fi

# --- Test 5: warning lists the CONTAINER env signal ---
if echo "$output" | grep -q "CONTAINER env set"; then
    assert_pass "warning lists CONTAINER env signal"
else
    assert_fail "missing CONTAINER signal, got $output"
fi

# --- Test 6: warning lists at least one mitigation ---
if echo "$output" | grep -q "Mount a persistent volume"; then
    assert_pass "warning lists persistent-volume mitigation"
else
    assert_fail "missing mitigation, got $output"
fi

# --- Test 7: DEVCONTAINER env triggers detection ---
output=$(run_hook DEVCONTAINER=1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "DEVCONTAINER env set"; then
    assert_pass "DEVCONTAINER env triggers detection"
else
    assert_fail "expected DEVCONTAINER detection, got rc=$rc output=$output"
fi

# --- Test 8: CODESPACES env triggers detection ---
output=$(run_hook CODESPACES=true)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "CODESPACES env set"; then
    assert_pass "CODESPACES env triggers detection"
else
    assert_fail "expected CODESPACES detection, got rc=$rc output=$output"
fi

# --- Test 9: REMOTE_CONTAINERS env triggers detection ---
output=$(run_hook REMOTE_CONTAINERS=true)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "REMOTE_CONTAINERS env set"; then
    assert_pass "REMOTE_CONTAINERS env triggers detection"
else
    assert_fail "expected REMOTE_CONTAINERS detection, got rc=$rc output=$output"
fi

# --- Test 10: hex-pattern hostname triggers detection ---
output=$(env -i \
    HOME="$TEST_ROOT" \
    PATH="$PATH" \
    CC_CLAUDE_HOME="$FAKE_HOME" \
    HOSTNAME="7b3a1f8d2c4e" \
    bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "hostname looks like a container ID"; then
    assert_pass "hex-pattern hostname triggers detection"
else
    assert_fail "expected hostname detection, got rc=$rc output=$output"
fi

# --- Test 11: settings.json with no mcpServers configured → silent (no MCP risk) ---
mkdir -p "$FAKE_HOME"
echo '{"theme": "dark"}' > "$FAKE_HOME/settings.json"
output=$(run_hook CONTAINER=docker)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "container + no MCP configured → silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 12: settings.json with mcpServers but empty approvals → warning ---
cat > "$FAKE_HOME/settings.json" <<'JSON'
{
  "mcpServers": {"slack": {"command": "slack-mcp"}, "github": {"command": "gh-mcp"}},
  "enabledMcpjsonServers": []
}
JSON
output=$(run_hook CONTAINER=docker)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "2 mcpServers configured but enabledMcpjsonServers is empty"; then
    assert_pass "container + configured-but-unapproved mcpServers → warning"
else
    assert_fail "expected warning with count, got rc=$rc output=$output"
fi

# --- Test 13: project-scoped mcpServers count toward reset signal ---
cat > "$FAKE_HOME/settings.json" <<'JSON'
{
  "projects": {
    "/home/user/foo": {"mcpServers": {"slack": {"command": "x"}}}
  }
}
JSON
output=$(run_hook CONTAINER=docker)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "mcpServers configured but enabledMcpjsonServers is empty"; then
    assert_pass "project-scoped mcpServers detected"
else
    assert_fail "expected project mcpServers detection, got rc=$rc output=$output"
fi

# --- Test 14: disable flag silences even when both layers match ---
rm -f "$FAKE_HOME/settings.json"
output=$(run_hook CONTAINER=docker CC_EPHEMERAL_CONTAINER_DISABLE=1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag → silent even when both layers match"
else
    assert_fail "expected disabled, got rc=$rc output=$output"
fi

# --- Test 15: multiple container signals → all listed ---
output=$(env -i \
    HOME="$TEST_ROOT" \
    PATH="$PATH" \
    CC_CLAUDE_HOME="$FAKE_HOME" \
    HOSTNAME="abc123def456" \
    CONTAINER=docker \
    DEVCONTAINER=1 \
    bash "$HOOK" 2>&1)
rc=$?
sig_count=$(echo "$output" | grep -cE "CONTAINER env set|DEVCONTAINER env set|hostname looks like")
if [ "$rc" -eq 0 ] && [ "$sig_count" -ge 3 ]; then
    assert_pass "multiple container signals all listed (got $sig_count)"
else
    assert_fail "expected ≥3 signals, got $sig_count output=$output"
fi

# --- Test 16: hook exits 0 (does not block session start) ---
if [ "$rc" -eq 0 ]; then
    assert_pass "hook exits 0 (non-blocking)"
else
    assert_fail "hook returned non-zero rc=$rc"
fi

# --- Test 17: CC_CLAUDE_HOME override is honored ---
ALT_HOME="$TEST_ROOT/alt-claude"
mkdir -p "$ALT_HOME"
output=$(env -i \
    HOME="$TEST_ROOT" \
    PATH="$PATH" \
    CC_CLAUDE_HOME="$ALT_HOME" \
    HOSTNAME="testhost" \
    CONTAINER=docker \
    bash "$HOOK" 2>&1)
rc=$?
# ALT_HOME exists but has no settings.json → should warn
if [ "$rc" -eq 0 ] && echo "$output" | grep -qF "settings.json is missing at $ALT_HOME/settings.json"; then
    assert_pass "CC_CLAUDE_HOME override honored in warning"
else
    assert_fail "expected ALT_HOME in output, got rc=$rc output=$output"
fi

# --- Test 18: hook handles malformed settings.json gracefully ---
mkdir -p "$FAKE_HOME"
echo 'not valid json {{{' > "$FAKE_HOME/settings.json"
output=$(run_hook CONTAINER=docker 2>&1)
rc=$?
# jq will fail on the file. mcp_configured comes back as 0, so the hook
# falls through to "no reset signal" and exits silently. That's the safe
# behavior — the hook does not crash the session start on bad JSON.
if [ "$rc" -eq 0 ]; then
    assert_pass "malformed settings.json → hook exits 0 (does not crash)"
else
    assert_fail "expected rc=0 on bad JSON, got rc=$rc output=$output"
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
