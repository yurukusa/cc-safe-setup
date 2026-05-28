#!/bin/bash
# Tests for cowork-claude-md-load-checker.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/cowork-claude-md-load-checker.sh"
PASS=0
FAIL=0

# Build a temp CLAUDE.md we can point the hook at
TMP_MD=$(mktemp /tmp/test-cowork-md.XXXXXX)
trap 'rm -f "$TMP_MD"' EXIT

cat > "$TMP_MD" <<'EOF'
# Project Rules
- Rule A: never commit secrets
- Rule B: small functions only
- Rule C: ask before deleting files
- Rule D: confirm before write operations to MCP tools
EOF

INPUT='{"session_id":"test-cowork"}'

run_hook() {
    echo "$INPUT" | CC_COWORK_MD_PATH="$1" bash "$HOOK" 2>&1 || true
}

run_hook_env() {
    local path="$1"; shift
    echo "$INPUT" | CC_COWORK_MD_PATH="$path" "$@" bash "$HOOK" 2>&1 || true
}

# --- Test 1: Fires when file exists and is non-trivial ---
output=$(run_hook "$TMP_MD")
if echo "$output" | grep -q "cowork-claude-md-load-checker"; then
    echo "  PASS: fires header when file exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should fire header for valid file"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: Prints the file content ---
output=$(run_hook "$TMP_MD")
if echo "$output" | grep -q "Rule A: never commit secrets"; then
    echo "  PASS: prints file content"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should print file content"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: References issue #62859 ---
output=$(run_hook "$TMP_MD")
if echo "$output" | grep -q "#62859"; then
    echo "  PASS: references #62859"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference #62859"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Silently skips when file does not exist ---
MISSING_PATH="/tmp/this-file-does-not-exist-cowork-$$"
output=$(run_hook "$MISSING_PATH")
if [ -z "$output" ]; then
    echo "  PASS: silently skips missing file"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent for missing file, got: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: Silently skips when file is below min size ---
TINY_MD=$(mktemp /tmp/test-cowork-tiny.XXXXXX)
echo "x" > "$TINY_MD"
output=$(run_hook "$TINY_MD")
if [ -z "$output" ]; then
    echo "  PASS: silently skips tiny file (below 50 byte default)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent for tiny file, got: $output"
    FAIL=$((FAIL + 1))
fi
rm -f "$TINY_MD"

# --- Test 6: Custom min size threshold ---
SMALL_MD=$(mktemp /tmp/test-cowork-small.XXXXXX)
echo "small content" > "$SMALL_MD"
output=$(echo "$INPUT" | CC_COWORK_MD_PATH="$SMALL_MD" CC_COWORK_MD_MIN_BYTES=5 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "small content"; then
    echo "  PASS: respects custom CC_COWORK_MD_MIN_BYTES override"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should fire for small file when MIN_BYTES=5"
    FAIL=$((FAIL + 1))
fi
rm -f "$SMALL_MD"

# --- Test 7: Cowork reminder line by default ---
output=$(run_hook "$TMP_MD")
if echo "$output" | grep -q "switch to Cowork"; then
    echo "  PASS: prints Cowork reminder by default"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should print Cowork reminder by default"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: CC_COWORK_MD_QUIET suppresses the reminder ---
output=$(echo "$INPUT" | CC_COWORK_MD_PATH="$TMP_MD" CC_COWORK_MD_QUIET=1 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "switch to Cowork"; then
    echo "  FAIL: CC_COWORK_MD_QUIET=1 should suppress reminder"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: CC_COWORK_MD_QUIET=1 suppresses reminder"
    PASS=$((PASS + 1))
fi

# --- Test 9: Content truncated when exceeds max ---
BIG_MD=$(mktemp /tmp/test-cowork-big.XXXXXX)
{
    for i in $(seq 1 200); do
        echo "Long line number $i with padding to consume bytes"
    done
} > "$BIG_MD"
output=$(echo "$INPUT" | CC_COWORK_MD_PATH="$BIG_MD" CC_COWORK_MD_MAX_CHARS=200 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "truncated at 200 chars"; then
    echo "  PASS: shows truncation notice when over MAX_CHARS"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should show truncation notice"
    FAIL=$((FAIL + 1))
fi
rm -f "$BIG_MD"

# --- Test 10: Exits 0 even when fires ---
echo "$INPUT" | CC_COWORK_MD_PATH="$TMP_MD" bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 when fires (advisory only)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: Exits 0 when file missing ---
echo "$INPUT" | CC_COWORK_MD_PATH="/tmp/missing-$$" bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 when file missing"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0 for missing, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: Handles empty stdin ---
output=$(echo "" | CC_COWORK_MD_PATH="$TMP_MD" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "cowork-claude-md-load-checker"; then
    echo "  PASS: handles empty stdin"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should still fire with empty stdin"
    FAIL=$((FAIL + 1))
fi

# --- Test 13: Handles no stdin at all ---
output=$(CC_COWORK_MD_PATH="$TMP_MD" bash "$HOOK" </dev/null 2>&1 || true)
if echo "$output" | grep -q "cowork-claude-md-load-checker"; then
    echo "  PASS: handles missing stdin"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should still fire with no stdin"
    FAIL=$((FAIL + 1))
fi

# --- Test 14: Optional log file is written ---
LOG_FILE=$(mktemp /tmp/test-cowork-log.XXXXXX)
rm -f "$LOG_FILE"
echo "$INPUT" | CC_COWORK_MD_PATH="$TMP_MD" CC_COWORK_MD_LOG="$LOG_FILE" bash "$HOOK" >/dev/null 2>&1
if [ -f "$LOG_FILE" ] && grep -q "file=$TMP_MD" "$LOG_FILE"; then
    echo "  PASS: writes log entry when CC_COWORK_MD_LOG set"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log file should contain entry"
    FAIL=$((FAIL + 1))
fi
rm -f "$LOG_FILE"

# --- Test 15: Log is not written when env var unset ---
LOG_FILE=$(mktemp /tmp/test-cowork-log2.XXXXXX)
rm -f "$LOG_FILE"
echo "$INPUT" | CC_COWORK_MD_PATH="$TMP_MD" bash "$HOOK" >/dev/null 2>&1
if [ ! -f "$LOG_FILE" ]; then
    echo "  PASS: no log written when CC_COWORK_MD_LOG unset"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should not write log without env var"
    FAIL=$((FAIL + 1))
fi
rm -f "$LOG_FILE"

# --- Test 16: Has SessionStart trigger documented ---
if grep -q "TRIGGER: SessionStart" "$HOOK"; then
    echo "  PASS: documents SessionStart trigger"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should document SessionStart trigger"
    FAIL=$((FAIL + 1))
fi

# --- Test 17: Defaults to ~/.claude/CLAUDE.md ---
if grep -q "\$HOME/.claude/CLAUDE.md" "$HOOK"; then
    echo "  PASS: defaults to ~/.claude/CLAUDE.md path"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should default to ~/.claude/CLAUDE.md"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: Header references 'SessionStart' so users grep for it ---
output=$(run_hook "$TMP_MD")
if echo "$output" | grep -q "SessionStart"; then
    echo "  PASS: output mentions SessionStart"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should mention SessionStart in output"
    FAIL=$((FAIL + 1))
fi

# --- Test 19: Output mentions CLI vs Cowork distinction ---
output=$(run_hook "$TMP_MD")
if echo "$output" | grep -q "CLI"; then
    echo "  PASS: output distinguishes CLI vs Cowork"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should distinguish CLI vs Cowork in output"
    FAIL=$((FAIL + 1))
fi

# --- Test 20: References related issue (#50669 visible in header file) ---
if grep -q "#50669" "$HOOK"; then
    echo "  PASS: hook header references related #50669"
    PASS=$((PASS + 1))
else
    echo "  FAIL: header should reference related issue"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "Tests: $((PASS + FAIL)) total, $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
