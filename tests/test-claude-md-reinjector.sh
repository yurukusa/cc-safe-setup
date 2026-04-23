#!/bin/bash
# Tests for claude-md-reinjector.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/claude-md-reinjector.sh"
PASS=0
FAIL=0
STATE_DIR="/tmp/cc-md-reinject"
SESSION_ID="test-$$"
COUNT_FILE="$STATE_DIR/${SESSION_ID}.count"

setup() {
    rm -f "$STATE_DIR"/*.count 2>/dev/null || true
    mkdir -p "$STATE_DIR"
}

# Build a temp CLAUDE.md we can point the hook at
TMP_MD=$(mktemp /tmp/test-claude-md.XXXXXX)
cat > "$TMP_MD" <<'EOF'
# Project Rules
- Rule A: never commit secrets
- Rule B: small functions only
- Rule C: ask before deleting files
EOF

INPUT='{"session_id":"'"$SESSION_ID"'","tool_name":"Read"}'

run_hook() {
    local every="${1:-50}"
    echo "$INPUT" | CC_MD_REINJECT_EVERY="$every" CC_MD_REINJECT_PATH="$TMP_MD" bash "$HOOK" 2>&1 || true
}

# --- Test 1: First call under threshold does NOT inject ---
setup
output=$(run_hook 50)
if echo "$output" | grep -q "re-injecting"; then
    echo "  FAIL: first call should not inject (count=1, every=50)"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: first call does not inject"
    PASS=$((PASS + 1))
fi

# --- Test 2: Counter increments ---
setup
run_hook 50 >/dev/null 2>&1
run_hook 50 >/dev/null 2>&1
run_hook 50 >/dev/null 2>&1
count=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
if [ "$count" = "3" ]; then
    echo "  PASS: counter increments to 3"
    PASS=$((PASS + 1))
else
    echo "  FAIL: counter should be 3, got $count"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: Inject fires on the N-th call ---
setup
# Set count to 1 already, N=2 → second call should inject
run_hook 2 >/dev/null 2>&1
output=$(run_hook 2)
if echo "$output" | grep -q "re-injecting"; then
    echo "  PASS: inject fires on N-th call (every=2)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should have injected on call #2 with every=2"
    echo "    output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Injected content contains CLAUDE.md rules ---
setup
run_hook 1 >/dev/null 2>&1   # first call injects (every=1)
output=$(echo "$INPUT" | CC_MD_REINJECT_EVERY=1 CC_MD_REINJECT_PATH="$TMP_MD" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "Rule A: never commit secrets"; then
    echo "  PASS: injected output contains CLAUDE.md content"
    PASS=$((PASS + 1))
else
    echo "  FAIL: injected output missing CLAUDE.md rules"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: Inject output mentions issue #49244 ---
setup
output=$(echo "$INPUT" | CC_MD_REINJECT_EVERY=1 CC_MD_REINJECT_PATH="$TMP_MD" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "49244"; then
    echo "  PASS: header mentions issue #49244"
    PASS=$((PASS + 1))
else
    echo "  FAIL: header should mention #49244"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Missing CLAUDE.md exits 0 silently (no crash) ---
setup
GHOST_PATH="/tmp/does-not-exist-$$/CLAUDE.md"
set +e
output=$(echo "$INPUT" | CC_MD_REINJECT_EVERY=1 CC_MD_REINJECT_PATH="$GHOST_PATH" bash "$HOOK" 2>&1)
rc=$?
set -e
if [ "$rc" = "0" ] && ! echo "$output" | grep -q "re-injecting"; then
    echo "  PASS: missing CLAUDE.md exits 0 silently"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0 with no injection, rc=$rc output=$output"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: Invalid JSON on stdin doesn't crash ---
setup
set +e
output=$(echo "not-json" | CC_MD_REINJECT_EVERY=1 CC_MD_REINJECT_PATH="$TMP_MD" bash "$HOOK" 2>&1)
rc=$?
set -e
if [ "$rc" = "0" ]; then
    echo "  PASS: invalid JSON does not crash (uses default session)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: invalid JSON crashed with rc=$rc"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: Truncation honored ---
BIG_MD=$(mktemp /tmp/test-claude-md-big.XXXXXX)
python3 -c "print('x' * 5000)" > "$BIG_MD"
setup
output=$(echo "$INPUT" | CC_MD_REINJECT_EVERY=1 CC_MD_REINJECT_PATH="$BIG_MD" CC_MD_REINJECT_MAX_CHARS=500 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "truncated at 500 chars"; then
    echo "  PASS: truncation marker emitted for oversized CLAUDE.md"
    PASS=$((PASS + 1))
else
    echo "  FAIL: truncation marker missing"
    FAIL=$((FAIL + 1))
fi
rm -f "$BIG_MD"

# --- Test 9: Log file written when CC_MD_REINJECT_LOG set ---
LOG_FILE=$(mktemp /tmp/test-reinject-log.XXXXXX)
rm "$LOG_FILE"
setup
echo "$INPUT" | CC_MD_REINJECT_EVERY=1 CC_MD_REINJECT_PATH="$TMP_MD" CC_MD_REINJECT_LOG="$LOG_FILE" bash "$HOOK" >/dev/null 2>&1 || true
if [ -f "$LOG_FILE" ] && grep -q "session=$SESSION_ID" "$LOG_FILE"; then
    echo "  PASS: log file written with session id"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log file missing or malformed"
    FAIL=$((FAIL + 1))
fi
rm -f "$LOG_FILE"

# --- Test 10: Different sessions have independent counters ---
setup
run_hook 50 >/dev/null 2>&1
INPUT_B='{"session_id":"other-'$$'","tool_name":"Read"}'
echo "$INPUT_B" | CC_MD_REINJECT_EVERY=50 CC_MD_REINJECT_PATH="$TMP_MD" bash "$HOOK" >/dev/null 2>&1 || true
count_a=$(cat "$STATE_DIR/${SESSION_ID}.count" 2>/dev/null || echo 0)
count_b=$(cat "$STATE_DIR/other-$$.count" 2>/dev/null || echo 0)
if [ "$count_a" = "1" ] && [ "$count_b" = "1" ]; then
    echo "  PASS: per-session counters isolated"
    PASS=$((PASS + 1))
else
    echo "  FAIL: counters should be independent (a=$count_a b=$count_b)"
    FAIL=$((FAIL + 1))
fi

# Cleanup
rm -f "$TMP_MD"
rm -f "$STATE_DIR"/*.count 2>/dev/null || true

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
