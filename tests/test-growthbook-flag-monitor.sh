#!/bin/bash
# Tests for growthbook-flag-monitor.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/growthbook-flag-monitor.sh"
PASS=0
FAIL=0

# Build temp dirs and cache files we control
TMP_ROOT=$(mktemp -d /tmp/test-growthbook.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

CACHE_FILE="$TMP_ROOT/cache.json"
STATE_DIR="$TMP_ROOT/state"

INPUT='{"session_id":"test-growthbook"}'

write_cache() {
    cat > "$CACHE_FILE"
}

reset_state() {
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR"
}

run_hook() {
    echo "$INPUT" | \
        CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" \
        CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" \
        bash "$HOOK" 2>&1 || true
}

run_hook_env() {
    local extra="$1"; shift
    echo "$INPUT" | \
        CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" \
        CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" \
        env $extra bash "$HOOK" 2>&1 || true
}

# --- Test 1: First run emits baseline notice ---
reset_state
write_cache <<'EOF'
{"tengu_permission_friction":{"value":true},"tengu_quill_harbor":{"value":false}}
EOF
output=$(run_hook)
if echo "$output" | grep -q "baseline snapshot recorded"; then
    echo "  PASS: first run emits baseline notice"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should emit baseline notice on first run: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: First run reports correct flag count ---
output=$(echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR.b" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "2 flags"; then
    echo "  PASS: reports correct flag count (2)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should report 2 flags: $output"
    FAIL=$((FAIL + 1))
fi
rm -rf "$STATE_DIR.b"

# --- Test 3: Second run with no changes shows no-change line ---
reset_state
write_cache <<'EOF'
{"tengu_a":{"value":1},"tengu_b":{"value":2}}
EOF
run_hook >/dev/null 2>&1
output=$(run_hook)
if echo "$output" | grep -q "no GrowthBook flag changes"; then
    echo "  PASS: second run with no changes reports no-change"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should report no changes: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Added flag triggers diff advisory ---
reset_state
write_cache <<'EOF'
{"tengu_a":{"value":1}}
EOF
run_hook >/dev/null 2>&1
write_cache <<'EOF'
{"tengu_a":{"value":1},"tengu_b":{"value":2}}
EOF
output=$(run_hook)
if echo "$output" | grep -q "added:.*1"; then
    echo "  PASS: detects added flag"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should detect added flag: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: Added flag name is listed ---
if echo "$output" | grep -q "+ tengu_b"; then
    echo "  PASS: lists added flag name"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should list 'tengu_b' as added"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Removed flag triggers diff advisory ---
reset_state
write_cache <<'EOF'
{"tengu_a":{"value":1},"tengu_b":{"value":2}}
EOF
run_hook >/dev/null 2>&1
write_cache <<'EOF'
{"tengu_a":{"value":1}}
EOF
output=$(run_hook)
if echo "$output" | grep -q "removed:.*1"; then
    echo "  PASS: detects removed flag"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should detect removed flag"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: Removed flag name is listed ---
if echo "$output" | grep -q "\- tengu_b"; then
    echo "  PASS: lists removed flag name"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should list 'tengu_b' as removed"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: Changed flag value triggers diff ---
reset_state
write_cache <<'EOF'
{"tengu_a":{"value":1}}
EOF
run_hook >/dev/null 2>&1
write_cache <<'EOF'
{"tengu_a":{"value":2}}
EOF
output=$(run_hook)
if echo "$output" | grep -q "changed:.*1"; then
    echo "  PASS: detects value change"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should detect value change"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: Changed flag name is listed with ~ ---
if echo "$output" | grep -q "~ tengu_a"; then
    echo "  PASS: lists changed flag name with ~"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should list 'tengu_a' as changed"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: Multi-axis diff (added + removed + changed) ---
reset_state
write_cache <<'EOF'
{"keep":{"value":1},"removeme":{"value":2},"changeme":{"value":"old"}}
EOF
run_hook >/dev/null 2>&1
write_cache <<'EOF'
{"keep":{"value":1},"addme":{"value":3},"changeme":{"value":"new"}}
EOF
output=$(run_hook)
if echo "$output" | grep -q "added:.*1" && echo "$output" | grep -q "removed:.*1" && echo "$output" | grep -q "changed:.*1"; then
    echo "  PASS: multi-axis diff (added + removed + changed)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should detect all three axes"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: References #62205 ---
if echo "$output" | grep -q "#62205\|62205"; then
    echo "  PASS: references #62205"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference #62205"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: References Cluster 10 ---
if echo "$output" | grep -q "Cluster 10"; then
    echo "  PASS: references Cluster 10"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference Cluster 10"
    FAIL=$((FAIL + 1))
fi

# --- Test 13: References ~9-minute sync cadence ---
if echo "$output" | grep -q "9-minute"; then
    echo "  PASS: references ~9-minute sync cadence"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference sync cadence"
    FAIL=$((FAIL + 1))
fi

# --- Test 14: Mentions tengu_permission_friction ---
if echo "$output" | grep -q "tengu_permission_friction"; then
    echo "  PASS: mentions tengu_permission_friction"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should mention tengu_permission_friction"
    FAIL=$((FAIL + 1))
fi

# --- Test 15: Silent when cache file does not exist ---
reset_state
RANDOM_PATH="/tmp/nonexistent-growthbook-$$"
output=$(echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$RANDOM_PATH" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1 || true)
if [ -z "$output" ]; then
    echo "  PASS: silent when cache file missing"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent for missing cache: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 16: CC_GROWTHBOOK_MONITOR_DISABLE silences ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
output=$(echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" CC_GROWTHBOOK_MONITOR_DISABLE=1 bash "$HOOK" 2>&1 || true)
if [ -z "$output" ]; then
    echo "  PASS: CC_GROWTHBOOK_MONITOR_DISABLE=1 silences"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent with DISABLE=1: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 17: CC_GROWTHBOOK_MONITOR_QUIET suppresses no-change line ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
run_hook >/dev/null 2>&1
output=$(echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" CC_GROWTHBOOK_MONITOR_QUIET=1 bash "$HOOK" 2>&1 || true)
if [ -z "$output" ]; then
    echo "  PASS: CC_GROWTHBOOK_MONITOR_QUIET=1 suppresses no-change line"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent with QUIET=1 and no diff: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: QUIET does NOT suppress diff advisory ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
run_hook >/dev/null 2>&1
write_cache <<'EOF'
{"flag_a":{"value":1},"flag_b":{"value":2}}
EOF
output=$(echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" CC_GROWTHBOOK_MONITOR_QUIET=1 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "GrowthBook flag set changed"; then
    echo "  PASS: QUIET does not suppress diff advisory"
    PASS=$((PASS + 1))
else
    echo "  FAIL: diff should fire even with QUIET set"
    FAIL=$((FAIL + 1))
fi

# --- Test 19: Always exits 0 (advisory only) ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 on first run"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 20: Exits 0 on diff ---
write_cache <<'EOF'
{"flag_a":{"value":1},"flag_b":{"value":2}}
EOF
echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 on diff"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0 on diff, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 21: Documents SessionStart trigger ---
if grep -q "TRIGGER: SessionStart" "$HOOK"; then
    echo "  PASS: documents SessionStart trigger"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should document SessionStart trigger"
    FAIL=$((FAIL + 1))
fi

# --- Test 22: Documents CLUSTER 10 ---
if grep -qE "CLUSTER: 10|Cluster 10" "$HOOK"; then
    echo "  PASS: documents CLUSTER 10"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should document CLUSTER 10"
    FAIL=$((FAIL + 1))
fi

# --- Test 23: Snapshot file is created in state dir ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
run_hook >/dev/null 2>&1
if [ -f "$STATE_DIR/snapshot.json" ]; then
    echo "  PASS: snapshot file created in state dir"
    PASS=$((PASS + 1))
else
    echo "  FAIL: snapshot file should be created"
    FAIL=$((FAIL + 1))
fi

# --- Test 24: Optional log file is written when LOG set ---
LOG_FILE="$TMP_ROOT/events.log"
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
echo "$INPUT" | \
    CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" \
    CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" \
    CC_GROWTHBOOK_MONITOR_LOG="$LOG_FILE" \
    bash "$HOOK" >/dev/null 2>&1
if [ -f "$LOG_FILE" ] && grep -q "event=baseline" "$LOG_FILE"; then
    echo "  PASS: writes baseline event to log"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log should contain baseline event"
    FAIL=$((FAIL + 1))
fi

# --- Test 25: Log records diff event with counts ---
write_cache <<'EOF'
{"flag_a":{"value":1},"flag_b":{"value":2}}
EOF
echo "$INPUT" | \
    CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" \
    CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" \
    CC_GROWTHBOOK_MONITOR_LOG="$LOG_FILE" \
    bash "$HOOK" >/dev/null 2>&1
if grep -q "event=diff added=1" "$LOG_FILE"; then
    echo "  PASS: log records diff event with counts"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log should record diff event"
    FAIL=$((FAIL + 1))
fi

# --- Test 26: Handles empty stdin ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
output=$(echo "" | CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "baseline snapshot"; then
    echo "  PASS: handles empty stdin"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should still fire with empty stdin"
    FAIL=$((FAIL + 1))
fi

# --- Test 27: Handles missing stdin ---
reset_state
write_cache <<'EOF'
{"flag_a":{"value":1}}
EOF
output=$(CC_GROWTHBOOK_MONITOR_PATH="$CACHE_FILE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" bash "$HOOK" </dev/null 2>&1 || true)
if echo "$output" | grep -q "baseline snapshot"; then
    echo "  PASS: handles missing stdin"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should fire with missing stdin"
    FAIL=$((FAIL + 1))
fi

# --- Test 28: Handles .claude.json form with nested cachedGrowthBookFeatures ---
reset_state
NESTED_CACHE="$TMP_ROOT/claude.json"
cat > "$NESTED_CACHE" <<'EOF'
{
    "version": "2.1.153",
    "cachedGrowthBookFeatures": {
        "tengu_a": {"value": 1},
        "tengu_b": {"value": 2}
    }
}
EOF
output=$(echo "$INPUT" | CC_GROWTHBOOK_MONITOR_PATH="$NESTED_CACHE" CC_GROWTHBOOK_MONITOR_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "2 flags"; then
    echo "  PASS: handles ~/.claude.json nested form"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should handle nested form: $output"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "Tests: $((PASS + FAIL)) total, $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
