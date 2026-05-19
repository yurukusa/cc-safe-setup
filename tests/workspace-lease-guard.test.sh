#!/bin/bash
# Tests for workspace-lease-guard.sh
HOOK="$(dirname "$0")/../examples/workspace-lease-guard.sh"
PASS=0; FAIL=0

# Use isolated lease dir for each test run
TEST_DIR=$(mktemp -d)
export CC_LEASE_DIR="$TEST_DIR/locks"
export CC_LEASE_HEARTBEAT_TTL=3
export CLAUDE_PROJECT_DIR="$TEST_DIR/repo"
mkdir -p "$CLAUDE_PROJECT_DIR" "$CC_LEASE_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

run_test() {
    local desc="$1" input="$2" expect_code="$3" expect_stderr="${4:-}"
    local stderr_file
    stderr_file=$(mktemp)
    result=$(echo "$input" | bash "$HOOK" 2>"$stderr_file"; echo $?)
    code=$(echo "$result" | tail -1)
    stderr=$(cat "$stderr_file")
    rm -f "$stderr_file"
    if [ "$code" = "$expect_code" ]; then
        if [ -z "$expect_stderr" ] || printf '%s' "$stderr" | grep -q "$expect_stderr"; then
            echo "PASS: $desc"
            PASS=$((PASS + 1))
        else
            echo "FAIL: $desc (expected stderr containing '$expect_stderr', got: $stderr)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "FAIL: $desc (expected exit $expect_code, got $code; stderr: $stderr)"
        FAIL=$((FAIL + 1))
    fi
}

reset_state() {
    rm -f "$CC_LEASE_DIR"/*.lease 2>/dev/null
}

# === SessionStart: fresh acquire ===
reset_state
export CLAUDE_SESSION_ID="session-a-1"
run_test "SessionStart on empty lease dir acquires lease" \
    '{"hook_event_name":"SessionStart"}' "0"

# Verify lease was written
LEASE_FILE=$(ls "$CC_LEASE_DIR"/*.lease 2>/dev/null | head -1)
if [ -n "$LEASE_FILE" ] && grep -q "session-a-1" "$LEASE_FILE"; then
    echo "PASS: Lease file contains agent id session-a-1"
    PASS=$((PASS + 1))
else
    echo "FAIL: Lease file missing or wrong content (file=$LEASE_FILE)"
    FAIL=$((FAIL + 1))
fi

# === SessionStart: same agent reacquires (idempotent) ===
export CLAUDE_SESSION_ID="session-a-1"
run_test "SessionStart same agent is idempotent" \
    '{"hook_event_name":"SessionStart"}' "0"

# === SessionStart: different agent BLOCKED while heartbeat fresh ===
export CLAUDE_SESSION_ID="session-b-2"
run_test "SessionStart different agent blocked when lease is fresh" \
    '{"hook_event_name":"SessionStart"}' "2" "held by another Claude session"

# === SessionStart: takeover after TTL expiry ===
sleep 4  # exceed CC_LEASE_HEARTBEAT_TTL of 3
export CLAUDE_SESSION_ID="session-b-2"
run_test "SessionStart takes over stale lease after TTL" \
    '{"hook_event_name":"SessionStart"}' "0" "took over a stale lease"

# === PreToolUse: holder refreshes heartbeat ===
reset_state
export CLAUDE_SESSION_ID="session-c-3"
echo '{"hook_event_name":"SessionStart"}' | bash "$HOOK" >/dev/null 2>&1
run_test "PreToolUse from holder refreshes heartbeat" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash"}' "0"

# === PreToolUse: sibling agent BLOCKED ===
export CLAUDE_SESSION_ID="session-d-4"
run_test "PreToolUse from sibling blocked when lease fresh" \
    '{"hook_event_name":"PreToolUse","tool_name":"Edit"}' "2" "sibling agent"

# === PreToolUse: implicit claim when no lease present ===
reset_state
export CLAUDE_SESSION_ID="session-e-5"
run_test "PreToolUse on empty lease dir claims implicitly" \
    '{"hook_event_name":"PreToolUse","tool_name":"Write"}' "0"

# === Stop: compare-and-delete releases lease only if holder ===
reset_state
export CLAUDE_SESSION_ID="session-f-6"
echo '{"hook_event_name":"SessionStart"}' | bash "$HOOK" >/dev/null 2>&1
LEASE_FILE=$(ls "$CC_LEASE_DIR"/*.lease 2>/dev/null | head -1)

# Stop from non-holder should NOT delete
export CLAUDE_SESSION_ID="session-g-7"
echo '{"hook_event_name":"Stop"}' | bash "$HOOK" >/dev/null 2>&1
if [ -f "$LEASE_FILE" ]; then
    echo "PASS: Stop from non-holder did not delete lease"
    PASS=$((PASS + 1))
else
    echo "FAIL: Stop from non-holder erroneously deleted lease"
    FAIL=$((FAIL + 1))
fi

# Stop from holder DOES delete
export CLAUDE_SESSION_ID="session-f-6"
echo '{"hook_event_name":"Stop"}' | bash "$HOOK" >/dev/null 2>&1
if [ ! -f "$LEASE_FILE" ]; then
    echo "PASS: Stop from holder released lease"
    PASS=$((PASS + 1))
else
    echo "FAIL: Stop from holder did not delete lease"
    FAIL=$((FAIL + 1))
fi

# === Disabled via CC_LEASE_DISABLE ===
CC_LEASE_DISABLE=1 run_test "CC_LEASE_DISABLE bypasses hook" \
    '{"hook_event_name":"SessionStart"}' "0"

# === No workspace identifiable: no-op ===
saved=$CLAUDE_PROJECT_DIR
unset CLAUDE_PROJECT_DIR
(cd / && run_test "No workspace identifiable: exit 0" \
    '{"hook_event_name":"SessionStart"}' "0")
export CLAUDE_PROJECT_DIR="$saved"

# === Unknown event: exit 0 ===
reset_state
run_test "Unknown event is no-op" \
    '{"hook_event_name":"PostToolUse","tool_name":"Bash"}' "0"

# === Empty input ===
reset_state
run_test "Empty input is no-op" '{}' "0"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
