#!/bin/bash
# Tests for memory-chain-audit.sh
HOOK="examples/memory-chain-audit.sh"
PASS=0 FAIL=0

assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }
assert_file_contains() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in $2)"; fi; }

LOG="${HOME}/.claude/logs/memory-chain.log"
mkdir -p "${HOME}/.claude/logs"
: > "$LOG"

# Test 1: Main turn logged (no memory call yet — first turn ignored pattern)
SESS="mem-test-$(date +%s%N)-1"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{"input_tokens":5000,"output_tokens":200}}}\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "main turn only exits 0" "$RC" 0
assert_file_contains "main cost logged" "$LOG" "5200"
rm -f "$TRANS"

# Test 2: Memory chain present — both costs logged
: > "$LOG"
SESS="mem-test-$(date +%s%N)-2"
TRANS=$(mktemp)
printf '{"type":"assistant","message":{"usage":{"input_tokens":5000,"output_tokens":200}}}\n' >> "$TRANS"
printf '{"type":"extractMemories","message":{"usage":{"input_tokens":4500,"output_tokens":150}}}\n' >> "$TRANS"
printf '%s' "$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS")" | bash "$HOOK" 2>&1
assert_file_contains "main 5200 logged" "$LOG" "5200"
assert_file_contains "memory 4650 logged" "$LOG" "4650"
rm -f "$TRANS"

# Test 3: TSV format (4 fields)
FIELDS=$(awk -F'\t' '{print NF}' "$LOG" | head -1)
if [ "$FIELDS" = "4" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 4 TSV fields, got $FIELDS"; fi

# Test 4: Missing session_id → silent no-op
OUT=$(printf '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing session_id exits 0" "$RC" 0

# Test 5: No transcript path → silent no-op
OUT=$(printf '{"session_id":"x"}' | bash "$HOOK" 2>&1)
RC=$?
assert_exit "no transcript exits 0" "$RC" 0

# Test 6: Malformed transcript → exits 0 gracefully
: > "$LOG"
SESS="mem-test-$(date +%s%N)-6"
TRANS=$(mktemp)
printf 'not-json\n' >> "$TRANS"
OUT=$(printf '{"session_id":"%s","transcript_path":"%s"}' "$SESS" "$TRANS" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "malformed transcript exits 0" "$RC" 0
rm -f "$TRANS"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
