#!/bin/bash
# Tests for daemon-zombie-worker-surfacer.sh — verifies the SessionStart
# hook detects orphaned/zombie background workers from `claude daemon status`
# and surfaces an advisory, staying silent in the healthy case.

set -uo pipefail

HOOK="${HOOK_OVERRIDE:-$(cd "$(dirname "$0")/.." && pwd)/examples/daemon-zombie-worker-surfacer.sh}"

PASS=0
FAIL=0
assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== daemon-zombie-worker-surfacer.sh tests ==="

# --- Test 1: healthy (daemon not running, 0 workers) → silent ---
STATUS_HEALTHY='not running

bg sessions:
  bg workers:   0 in roster.json (control unreachable)
  roster.json:  absent'
out=$(CC_DAEMON_STATUS_CMD="printf '%s' \"\$STATUS_HEALTHY\"" STATUS_HEALTHY="$STATUS_HEALTHY" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then assert_pass "healthy → silent, exit 0"; else assert_fail "healthy should be silent (rc=$rc, out='$out')"; fi

# --- Test 2: live workers (8 registered) → advisory with count ---
STATUS_WORKERS='version: 2.1.169
bg workers:   8 running (control.sock), 8 in roster.json
holding this daemon open:
  8 bg workers running'
out=$(CC_DAEMON_STATUS_CMD="printf '%s' \"\$S\"" S="$STATUS_WORKERS" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "8 background worker(s) still registered"; then
    assert_pass "live workers → advisory names the count"
else assert_fail "live workers should warn with count (rc=$rc, out='$out')"; fi

# --- Test 3: version skew (orphans) → advisory mentions orphans ---
STATUS_SKEW='version: 2.1.169
bg workers:   8 running (control.sock), 8 in roster.json
              5 from a different CLI version'
out=$(CC_DAEMON_STATUS_CMD="printf '%s' \"\$S\"" S="$STATUS_SKEW" bash "$HOOK" 2>&1)
rc=$?
if printf '%s' "$out" | grep -q "5 of them are from a different CLI version"; then
    assert_pass "version skew → advisory names the orphan count"
else assert_fail "version skew should be surfaced (rc=$rc, out='$out')"; fi

# --- Test 4: disable flag → silent even with workers present ---
out=$(CC_DAEMON_SURFACER_DISABLE=1 CC_DAEMON_STATUS_CMD="printf '%s' \"\$S\"" S="$STATUS_WORKERS" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then assert_pass "disable flag → silent"; else assert_fail "disable flag should silence (rc=$rc, out='$out')"; fi

# --- Test 5: empty status (timeout/error) → fail-open silent ---
out=$(CC_DAEMON_STATUS_CMD="printf '%s' ''" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then assert_pass "empty status → fail-open silent"; else assert_fail "empty status should be silent (rc=$rc, out='$out')"; fi

# --- Test 6: advisory includes the recovery steps (claude agents --json) ---
out=$(CC_DAEMON_STATUS_CMD="printf '%s' \"\$S\"" S="$STATUS_WORKERS" bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q "claude agents --json"; then
    assert_pass "advisory includes inspect command"
else assert_fail "advisory should include 'claude agents --json'"; fi

# --- Test 7: non-blocking (exit 0) even when warning ---
out=$(CC_DAEMON_STATUS_CMD="printf '%s' \"\$S\"" S="$STATUS_SKEW" bash "$HOOK" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then assert_pass "non-blocking: exit 0 when warning"; else assert_fail "should exit 0 (non-blocking), got $rc"; fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
