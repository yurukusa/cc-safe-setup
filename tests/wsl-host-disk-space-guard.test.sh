#!/bin/bash
# Tests for wsl-host-disk-space-guard.sh
# Run: bash tests/wsl-host-disk-space-guard.test.sh
#
# Note: this hook reads real `df` output. We can't easily mock the
# filesystem, so we test what we can deterministically:
#   1. The hook exits 0 on a healthy system (most CI environments).
#   2. The hook respects the DISABLE flag.
#   3. The hook does not trip on environments with no /mnt/c.
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/wsl-host-disk-space-guard.sh"

run_hook() {
    local input="$1" expected_exit="$2" desc="$3" extra_env="${4:-}"
    local actual_exit=0
    if [ -n "$extra_env" ]; then
        # shellcheck disable=SC2086
        echo "$input" | env $extra_env bash "$HOOK" >/dev/null 2>/dev/null || actual_exit=$?
    else
        echo "$input" | bash "$HOOK" >/dev/null 2>/dev/null || actual_exit=$?
    fi
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "wsl-host-disk-space-guard.sh tests"
echo ""

# --- DISABLE flag bypasses everything (always exits 0) ---
run_hook '{"tool_input":{"command":"echo hello"}}' 0 "DISABLE flag exits 0" "CC_HOST_DISK_DISABLE=1 CC_HOST_DISK_BLOCK_PCT=0"

# --- With block thresholds at 100, never trips block (any used % is < 100 + small margin) ---
# We use 101 so even a 100%-full disk stays under threshold.
run_hook '{"tool_input":{"command":"echo hello"}}' 0 "Generous thresholds: no block" "CC_HOST_DISK_BLOCK_PCT=101 CC_LINUX_DISK_BLOCK_PCT=101 CC_HOST_DISK_WARN_PCT=101 CC_LINUX_DISK_WARN_PCT=101"

# --- Block when host threshold is set absurdly low (and /mnt/c exists or doesn't) ---
# If /mnt/c does not exist (non-WSL CI), block only triggers from / or /home,
# whose usage is generally well above 0%. Use threshold 0 to force the block branch.
run_hook '{"tool_input":{"command":"echo hello"}}' 2 "Block when LINUX_BLOCK threshold is 0" "CC_LINUX_DISK_BLOCK_PCT=0"

# --- Empty / missing input ---
run_hook '{}' 0 "Allow empty input on healthy system" "CC_HOST_DISK_BLOCK_PCT=101 CC_LINUX_DISK_BLOCK_PCT=101"
run_hook '{"tool_input":{}}' 0 "Allow missing command" "CC_HOST_DISK_BLOCK_PCT=101 CC_LINUX_DISK_BLOCK_PCT=101"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) tests"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
