#!/bin/bash
# Tests for post-credential-failure-destructive-guard.sh
# Run: bash tests/test-post-credential-failure-destructive-guard.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/post-credential-failure-destructive-guard.sh"
STATE_FILE="/tmp/cc-cred-failure-${PPID:-0}"

cleanup() {
    rm -f /tmp/cc-cred-failure-*
}
cleanup

# Find whichever state file was created (PPID may differ between test runner and hook)
get_state_file() {
    ls -t /tmp/cc-cred-failure-* 2>/dev/null | head -1
}

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

echo "post-credential-failure-destructive-guard.sh tests"
echo ""

# --- Empty input pass-through ---
test_hook '' 0 "Empty input passes through"
test_hook '{}' 0 "Empty JSON passes through"
test_hook '{"tool_name":"Edit"}' 0 "Non-Bash tool passes through"

# --- PostToolUse: success path (no state change) ---
test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":0,"stdout":"ok"}}' 0 "PostToolUse: successful command exits 0"

# --- PostToolUse: non-credential failure (no state file) ---
test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"file not found"}}' 0 "PostToolUse: non-credential error exits 0"
if [ -f "$STATE_FILE" ]; then
    echo "  FAIL: State file unexpectedly created after non-credential error"
    FAIL=$((FAIL + 1))
    rm -f "$STATE_FILE"
else
    echo "  PASS: State file NOT created after non-credential error"
    PASS=$((PASS + 1))
fi

# --- PostToolUse: credential failure variants ---
check_state_after() {
    local input="$1" desc="$2"
    cleanup
    echo "$input" | bash "$HOOK" >/dev/null 2>&1
    local f
    f=$(get_state_file)
    if [ -n "$f" ]; then
        echo "  PASS: state file created ($desc)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: state file missing ($desc)"
        FAIL=$((FAIL + 1))
    fi
}

cleanup
test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"credential mismatch: unauthorized"}}' 0 "PostToolUse: credential mismatch sets state (exit 0)"
check_state_after '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"credential mismatch: unauthorized"}}' "credential mismatch"

test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"auth failed for user"}}' 0 "PostToolUse: auth failed sets state"
check_state_after '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"auth failed for user"}}' "auth failed"

test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"permission denied"}}' 0 "PostToolUse: permission denied sets state"
check_state_after '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"permission denied"}}' "permission denied"

test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"401 Unauthorized"}}' 0 "PostToolUse: 401 sets state"
check_state_after '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"401 Unauthorized"}}' "401"

test_hook '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"invalid token: expired"}}' 0 "PostToolUse: invalid token sets state"
check_state_after '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"invalid token: expired"}}' "invalid token"

# --- PostToolUse: success after failure resets state ---
cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"credential mismatch"}}' | bash "$HOOK" >/dev/null 2>&1 || true
F=$(get_state_file); if [ -n "$F" ]; then echo "  PASS: state set after credential mismatch"; PASS=$((PASS + 1)); fi
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":0,"stdout":"recovered"}}' | bash "$HOOK" >/dev/null 2>&1 || true
[ ! -f "$STATE_FILE" ] && echo "  PASS: state cleared after success" && PASS=$((PASS + 1)) || (echo "  FAIL: state not cleared after success"; FAIL=$((FAIL + 1)))

# --- PreToolUse: no state file = pass through ---
cleanup
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /data"}}' 0 "PreToolUse: rm -rf without prior failure passes"
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"DROP DATABASE prod"}}' 0 "PreToolUse: DROP DATABASE without prior failure passes"

# --- PreToolUse: state file present + destructive = BLOCK ---
cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"credential mismatch"}}' | bash "$HOOK" >/dev/null 2>&1
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /data"}}' 2 "PreToolUse: rm -rf after credential failure BLOCKS"

cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"401 unauthorized"}}' | bash "$HOOK" >/dev/null 2>&1
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"DROP DATABASE prod"}}' 2 "PreToolUse: DROP DATABASE after 401 BLOCKS"

cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"auth failed"}}' | bash "$HOOK" >/dev/null 2>&1
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~10"}}' 2 "PreToolUse: git reset --hard after auth failure BLOCKS"

cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"permission denied"}}' | bash "$HOOK" >/dev/null 2>&1
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"railway volume delete prod"}}' 2 "PreToolUse: railway volume delete after permission denied BLOCKS"

cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"invalid token"}}' | bash "$HOOK" >/dev/null 2>&1
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"kubectl delete deployment prod"}}' 2 "PreToolUse: kubectl delete after invalid token BLOCKS"

# --- PreToolUse: state present + non-destructive = pass ---
cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"credential mismatch"}}' | bash "$HOOK" >/dev/null 2>&1
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' 0 "PreToolUse: ls after credential failure passes"
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat /etc/hostname"}}' 0 "PreToolUse: cat after credential failure passes"
test_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' 0 "PreToolUse: git status after credential failure passes"

# --- Disable flag ---
cleanup
echo '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_result":{"exitCode":1,"stderr":"credential mismatch"}}' | bash "$HOOK" >/dev/null 2>&1
CC_CRED_FAILURE_DISABLE=1 bash "$HOOK" <<< '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /data"}}' >/dev/null 2>&1
ACTUAL=$?
if [ "$ACTUAL" -eq 0 ]; then
    echo "  PASS: CC_CRED_FAILURE_DISABLE=1 bypasses the block"
    PASS=$((PASS + 1))
else
    echo "  FAIL: CC_CRED_FAILURE_DISABLE=1 should bypass (got $ACTUAL)"
    FAIL=$((FAIL + 1))
fi

# --- Final cleanup ---
cleanup

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
