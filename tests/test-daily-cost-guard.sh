#!/bin/bash
# Tests for daily-cost-guard.sh
HOOK="examples/daily-cost-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Setup: isolated log dir
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
LOG_DIR="$TMPDIR/cost-log"
TODAY=$(date +%Y-%m-%d)

# Helper to write a fake transcript line with usage block
make_transcript() {
    local FILE="$1" INPUT="$2" OUTPUT="$3" CR="$4" CW="$5"
    printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' \
        "$INPUT" "$OUTPUT" "$CR" "$CW" > "$FILE"
}

# Test 1: No transcript path, silent pass
OUT=$(echo '{}' | CC_DAILY_COST_LOG_DIR="$LOG_DIR" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no transcript no warning" "$OUT" "daily-cost-guard"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Transcript file missing, silent pass
OUT=$(printf '{"transcript_path":"%s/missing.jsonl"}\n' "$TMPDIR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "missing transcript no warning" "$OUT" "daily-cost-guard"
assert_exit "missing transcript exit 0" "$RC" "0"

# Test 3: Empty transcript file, silent pass
TR="$TMPDIR/empty.jsonl"
: > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty transcript no warning" "$OUT" "daily-cost-guard"
assert_exit "empty transcript exit 0" "$RC" "0"

# Test 4: Small usage stays under all thresholds
LOG_DIR_T4="$TMPDIR/test4"
TR="$TMPDIR/small.jsonl"
make_transcript "$TR" 1000 500 0 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T4" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "small usage no warning" "$OUT" "daily-cost-guard"
assert_exit "small usage exit 0" "$RC" "0"
# Verify log was written
[ -f "$LOG_DIR_T4/$TODAY.jsonl" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: log file not created"; }

# Test 5: Large single turn crosses warning threshold (Sonnet pricing)
# Need ~$3.50 in single turn. Output costs $15/M, so need 233K output tokens
LOG_DIR_T5="$TMPDIR/test5"
TR="$TMPDIR/warn.jsonl"
make_transcript "$TR" 0 250000 0 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T5" bash "$HOOK" 2>&1)
RC=$?
assert_contains "warn threshold triggers warning" "$OUT" "警告閾値に達しました"
assert_exit "warn threshold advisory exit 0" "$RC" "0"

# Test 6: Daily limit exceeded triggers stronger warning
LOG_DIR_T6="$TMPDIR/test6"
TR="$TMPDIR/limit.jsonl"
make_transcript "$TR" 0 400000 0 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T6" bash "$HOOK" 2>&1)
RC=$?
assert_contains "daily limit triggers strong warning" "$OUT" "想定上限を超えました"
assert_exit "daily limit default advisory exit 0" "$RC" "0"

# Test 7: Daily limit with block mode exits 2
LOG_DIR_T7="$TMPDIR/test7"
TR="$TMPDIR/limit-block.jsonl"
make_transcript "$TR" 0 400000 0 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T7" CC_DAILY_COST_BLOCK=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "block mode warns" "$OUT" "想定上限を超えました"
assert_exit "block mode exit 2" "$RC" "2"

# Test 8: Multiple turns accumulate to exceed limit
LOG_DIR_T8="$TMPDIR/test8"
TR="$TMPDIR/accum.jsonl"
# First turn: $2.25 (just under warn)
make_transcript "$TR" 0 150000 0 0
printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T8" bash "$HOOK" >/dev/null 2>&1
# Second turn: another $2.25 → total $4.50 > warn $3.50
make_transcript "$TR" 0 150000 0 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T8" bash "$HOOK" 2>&1)
assert_contains "accumulated warns" "$OUT" "警告閾値に達しました"

# Test 9: Opus model uses higher pricing
LOG_DIR_T9="$TMPDIR/test9"
TR="$TMPDIR/opus.jsonl"
# 50K output × $75/M = $3.75 → exceeds warn under opus pricing
make_transcript "$TR" 0 50000 0 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T9" CC_DAILY_COST_MODEL=opus bash "$HOOK" 2>&1)
assert_contains "opus pricing crosses warn" "$OUT" "警告閾値に達しました"

# Test 10: Custom thresholds respected
LOG_DIR_T10="$TMPDIR/test10"
TR="$TMPDIR/custom.jsonl"
make_transcript "$TR" 0 10000 0 0
# 10K out × $15/M = $0.15 — exceeds custom warn $0.10
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T10" CC_DAILY_WARN_USD=0.10 CC_DAILY_LIMIT_USD=10 bash "$HOOK" 2>&1)
assert_contains "custom warn threshold honoured" "$OUT" "警告閾値に達しました"

# Test 11: Cache-only usage is logged but cheap
LOG_DIR_T11="$TMPDIR/test11"
TR="$TMPDIR/cache.jsonl"
# 100K cache_read at $0.30/M = $0.03 — well under all thresholds
make_transcript "$TR" 0 0 100000 0
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T11" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "cache-only no warning" "$OUT" "daily-cost-guard"
assert_exit "cache-only exit 0" "$RC" "0"
# Confirm log written
[ -f "$LOG_DIR_T11/$TODAY.jsonl" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: cache-only log not created"; }

# Test 12: Transcript with no usage block, silent pass
LOG_DIR_T12="$TMPDIR/test12"
TR="$TMPDIR/no-usage.jsonl"
printf '{"type":"user","message":{"role":"user","content":"hello"}}\n' > "$TR"
OUT=$(printf '{"transcript_path":"%s"}\n' "$TR" | CC_DAILY_COST_LOG_DIR="$LOG_DIR_T12" bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "no usage no warning" "$OUT" "daily-cost-guard"
assert_exit "no usage exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
