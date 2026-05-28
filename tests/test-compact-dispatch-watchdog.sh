#!/bin/bash
# Tests for compact-dispatch-watchdog.sh
HOOK="examples/compact-dispatch-watchdog.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

mk_usage_line() {
    local in_tok="$1" cache_read="$2" cache_creation="$3"
    printf '{"message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":100}}}\n' \
        "$in_tok" "$cache_read" "$cache_creation"
}

# Test 1: No transcript path → silent pass
OUT=$(echo '{}' | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no transcript silent" "$OUT" "compact_boundary"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Transcript exists but no usage block → silent pass
TR="$TMPDIR/t2.jsonl"
echo '{"message":{"role":"user"}}' > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no usage block silent" "$OUT" "Context at"
assert_exit "no usage exit 0" "$RC" "0"

# Test 3: Usage below threshold (50K of 200K = 25%) → silent pass
TR="$TMPDIR/t3.jsonl"
mk_usage_line 30000 15000 5000 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "below threshold silent" "$OUT" "Context at"
assert_exit "below threshold exit 0" "$RC" "0"

# Test 4: Usage at threshold (170K of 200K = 85%) → no compact event → warn
TR="$TMPDIR/t4.jsonl"
mk_usage_line 10000 150000 10000 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "threshold + no compact warns" "$OUT" "Context at"
assert_contains "warning cites issue" "$OUT" "#63015"
assert_contains "warning cites cluster" "$OUT" "Cluster 10"
assert_contains "warning suggests /compact" "$OUT" "/compact"
assert_exit "threshold + no compact exit 0" "$RC" "0"

# Test 5: Usage at threshold but compact_boundary present in recent window → silent
TR="$TMPDIR/t5.jsonl"
mk_usage_line 10000 150000 10000 > "$TR"
echo '{"compact_boundary":"true","summary":"…"}' >> "$TR"
mk_usage_line 11000 151000 11000 >> "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "compact present silences warn" "$OUT" "Context at"
assert_exit "compact present exit 0" "$RC" "0"

# Test 6: Above threshold (190K of 200K = 95%) → no compact → warn with pct
TR="$TMPDIR/t6.jsonl"
mk_usage_line 20000 160000 10000 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "above threshold warns" "$OUT" "Context at"
assert_contains "pct includes 95" "$OUT" "95"
assert_exit "above threshold exit 0" "$RC" "0"

# Test 7: Custom window 1M → 600K = 60% → silent
TR="$TMPDIR/t7.jsonl"
mk_usage_line 100000 450000 50000 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_WINDOW=1000000 bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "1M window below threshold silent" "$OUT" "Context at"
assert_exit "1M window exit 0" "$RC" "0"

# Test 8: Custom window 1M → 900K = 90% → warn
TR="$TMPDIR/t8.jsonl"
mk_usage_line 50000 800000 50000 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_WINDOW=1000000 bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "1M window above threshold warns" "$OUT" "Context at"
assert_exit "1M window warn exit 0" "$RC" "0"

# Test 9: Disable env wins even when triggered
TR="$TMPDIR/t9.jsonl"
mk_usage_line 20000 160000 10000 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_DISABLE=1 bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable silences" "$OUT" "Context at"
assert_exit "disable exit 0" "$RC" "0"

# Test 10: Custom threshold 0.5 makes 60K of 200K (30%) silent, 110K (55%) warn
TR="$TMPDIR/t10a.jsonl"
mk_usage_line 20000 40000 0 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_THRESHOLD=0.5 bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "custom thresh 30% silent" "$OUT" "Context at"
assert_exit "custom thresh below exit 0" "$RC" "0"

TR="$TMPDIR/t10b.jsonl"
mk_usage_line 20000 90000 0 > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_THRESHOLD=0.5 bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "custom thresh 55% warns" "$OUT" "Context at"
assert_exit "custom thresh above exit 0" "$RC" "0"

# Test 11: Override transcript via env (test convenience)
TR="$TMPDIR/t11.jsonl"
mk_usage_line 10000 160000 10000 > "$TR"
OUT=$(echo '{}' | CC_COMPACT_WATCHDOG_TRANSCRIPT="$TR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "env transcript triggers warn" "$OUT" "Context at"
assert_exit "env transcript exit 0" "$RC" "0"

# Test 12: Lookback window — compact event outside window does NOT silence
TR="$TMPDIR/t12.jsonl"
echo '{"compact_boundary":"true"}' > "$TR"
for i in $(seq 1 250); do
    echo '{"message":{"role":"user","content":"…"}}' >> "$TR"
done
mk_usage_line 10000 160000 10000 >> "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_LOOKBACK=200 bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "compact outside lookback still warns" "$OUT" "Context at"
assert_exit "lookback exit 0" "$RC" "0"

# Test 13: Lookback wide enough to see the old compact event silences
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | CC_COMPACT_WATCHDOG_LOOKBACK=500 bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "wide lookback sees compact" "$OUT" "Context at"
assert_exit "wide lookback exit 0" "$RC" "0"

# Test 14: Missing usage values default to 0 (graceful) — input only
TR="$TMPDIR/t14.jsonl"
printf '{"message":{"usage":{"input_tokens":180000,"output_tokens":50}}}\n' > "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "input-only above threshold warns" "$OUT" "Context at"
assert_exit "input-only exit 0" "$RC" "0"

# Test 15: Exit 0 even when stdin is missing entirely (Stop hook with no payload)
TR="$TMPDIR/t15.jsonl"
mk_usage_line 10000 160000 10000 > "$TR"
OUT=$(CC_COMPACT_WATCHDOG_TRANSCRIPT="$TR" bash "$HOOK_ABS" </dev/null 2>&1); RC=$?
assert_contains "missing stdin handled" "$OUT" "Context at"
assert_exit "missing stdin exit 0" "$RC" "0"

# Test 16: Latest usage wins when multiple usage blocks exist
TR="$TMPDIR/t16.jsonl"
mk_usage_line 10000 5000 0 > "$TR"
mk_usage_line 5000 5000 0 >> "$TR"
mk_usage_line 20000 160000 10000 >> "$TR"
OUT=$(echo "{\"transcript_path\":\"$TR\"}" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "latest usage drives decision" "$OUT" "Context at"
assert_exit "latest usage exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
