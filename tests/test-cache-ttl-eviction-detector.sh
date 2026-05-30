#!/bin/bash
# Tests for cache-ttl-eviction-detector.sh
HOOK="$(dirname "$0")/../examples/cache-ttl-eviction-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-ttl-test.XXXXXX"
}

run_test() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing cache-ttl-eviction-detector.sh"
echo "======================================"

# Test 1: empty payload, no usage → silent exit, no state
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
echo '{"session_id":"s1","tool_name":"Read"}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ ! -f "$STATE" ] && [ ! -f "$LOG" ]; then
  run_test "empty payload → no state/log written" "pass"
else
  run_test "empty payload → no state/log written" "fail"
fi
rm -rf "$TEST_DIR"

# Test 2: first event writes state but does not alert (no previous gap to measure)
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":1000,"cache_creation_input_tokens":100}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
if [ -f "$STATE" ] && [ ! -f "$LOG" ] && [ -z "$out" ]; then
  run_test "first event writes state, no alert" "pass"
else
  run_test "first event writes state, no alert" "fail"
fi
rm -rf "$TEST_DIR"

# Test 3: short gap (under threshold) → no alert even with low hit ratio
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
RECENT=$((NOW - 60))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$RECENT" > "$STATE"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
if [ ! -f "$LOG" ] && [ -z "$out" ]; then
  run_test "short gap (60s) → no alert" "pass"
else
  run_test "short gap (60s) → no alert (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 4: long gap + low hit ratio → alert
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
LONG_AGO=$((NOW - 600))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$LONG_AGO" > "$STATE"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
if [ -f "$LOG" ] && echo "$out" | grep -q "probable prompt-cache TTL eviction"; then
  run_test "long gap (10min) + 0% hit → alert" "pass"
else
  run_test "long gap (10min) + 0% hit → alert (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 5: long gap + high hit ratio → no alert (cache survived somehow)
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
LONG_AGO=$((NOW - 600))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$LONG_AGO" > "$STATE"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":80000,"cache_creation_input_tokens":1000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
if [ ! -f "$LOG" ] && [ -z "$out" ]; then
  run_test "long gap + 99% hit → no alert" "pass"
else
  run_test "long gap + 99% hit → no alert (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 6: cross-session gap → no alert (session boundary, not TTL eviction)
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
LONG_AGO=$((NOW - 600))
printf '{"last_event_ts":%s,"last_session":"old_session"}\n' "$LONG_AGO" > "$STATE"
out=$(echo '{"session_id":"new_session","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
if [ ! -f "$LOG" ] && [ -z "$out" ]; then
  run_test "cross-session gap → no alert" "pass"
else
  run_test "cross-session gap → no alert (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 7: silent mode → log written, no stderr
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
LONG_AGO=$((NOW - 600))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$LONG_AGO" > "$STATE"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" CC_TTL_EVICT_SILENT=1 bash "$HOOK" 2>&1)
if [ -f "$LOG" ] && [ -z "$out" ]; then
  run_test "silent mode → log only, no stderr" "pass"
else
  run_test "silent mode → log only, no stderr (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 8: custom gap threshold (180s) → 200s gap triggers (above 180s)
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
AGO=$((NOW - 200))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$AGO" > "$STATE"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" CC_TTL_EVICT_GAP_SECONDS=180 bash "$HOOK" 2>&1)
if [ -f "$LOG" ] && echo "$out" | grep -q "TTL eviction"; then
  run_test "custom gap threshold (180s) → triggers at 200s gap" "pass"
else
  run_test "custom gap threshold → triggers at 200s gap (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 9: custom hit floor (0.80) → 60% hit triggers (below 80%)
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
LONG_AGO=$((NOW - 600))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$LONG_AGO" > "$STATE"
# cache_read=60000, cache_creation=40000 → hit ratio = 0.60
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":60000,"cache_creation_input_tokens":40000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" CC_TTL_EVICT_HIT_FLOOR=0.80 bash "$HOOK" 2>&1)
if [ -f "$LOG" ] && echo "$out" | grep -q "TTL eviction"; then
  run_test "custom hit floor (0.80) → triggers at 60% hit" "pass"
else
  run_test "custom hit floor → triggers at 60% hit (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 10: malformed state file → exit cleanly, write fresh state
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
echo "not json" > "$STATE"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":1000,"cache_creation_input_tokens":100}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if grep -q '"last_event_ts"' "$STATE" 2>/dev/null; then
  run_test "malformed state → recovers, writes fresh state" "pass"
else
  run_test "malformed state → recovers, writes fresh state" "fail"
fi
rm -rf "$TEST_DIR"

# Test 11: zero usage values (cache_read=0, cache_creation=0) → exit silently
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ ! -f "$STATE" ] && [ ! -f "$LOG" ]; then
  run_test "zero usage values → exit silently" "pass"
else
  run_test "zero usage values → exit silently" "fail"
fi
rm -rf "$TEST_DIR"

# Test 12: transcript fallback when payload missing usage
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
TRANSCRIPT="$TEST_DIR/transcript.jsonl"
NOW=$(date -u +%s)
LONG_AGO=$((NOW - 600))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$LONG_AGO" > "$STATE"
# create a transcript with usage at the end
echo '{"message":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' > "$TRANSCRIPT"
out=$(printf '{"session_id":"s1","tool_name":"Read","transcript_path":"%s"}' "$TRANSCRIPT" | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
if [ -f "$LOG" ] && echo "$out" | grep -q "TTL eviction"; then
  run_test "transcript fallback → reads usage from transcript" "pass"
else
  run_test "transcript fallback (got: $out)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 13: state updates between events (regression-style)
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
# First event
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":1000,"cache_creation_input_tokens":100}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>/dev/null
TS1=$(jq -r '.last_event_ts' "$STATE" 2>/dev/null)
# Second event with same session
sleep 1
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":1500,"cache_creation_input_tokens":80}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>/dev/null
TS2=$(jq -r '.last_event_ts' "$STATE" 2>/dev/null)
if [ -n "$TS1" ] && [ -n "$TS2" ] && [ "$TS2" -gt "$TS1" ]; then
  run_test "state updates between events" "pass"
else
  run_test "state updates between events (ts1=$TS1 ts2=$TS2)" "fail"
fi
rm -rf "$TEST_DIR"

# Test 14: shellcheck (if available)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$HOOK" 2>&1; then
    run_test "shellcheck clean" "pass"
  else
    run_test "shellcheck clean" "fail"
  fi
else
  echo "  SKIP: shellcheck not installed"
fi

# Test 15: hook is executable
if [ -x "$HOOK" ]; then
  run_test "hook script is executable" "pass"
else
  run_test "hook script is executable" "fail"
fi

# Test 16: hook handles missing tool_response key
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
echo '{"session_id":"s1","tool_name":"Read"}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ ! -f "$STATE" ] && [ ! -f "$LOG" ]; then
  run_test "missing tool_response → exit silently" "pass"
else
  run_test "missing tool_response → exit silently" "fail"
fi
rm -rf "$TEST_DIR"

# Test 17: very long gap (1 hour) records correctly
TEST_DIR=$(mktempd)
STATE="$TEST_DIR/state.json"
LOG="$TEST_DIR/evictions.jsonl"
NOW=$(date -u +%s)
ONE_HOUR_AGO=$((NOW - 3600))
printf '{"last_event_ts":%s,"last_session":"s1"}\n' "$ONE_HOUR_AGO" > "$STATE"
out=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":50000}}}' | \
  CC_TTL_EVICT_STATE="$STATE" CC_TTL_EVICT_LOG="$LOG" bash "$HOOK" 2>&1)
gap_logged=$(jq -r '.gap_seconds' "$LOG" 2>/dev/null)
if [ -n "$gap_logged" ] && [ "$gap_logged" -ge 3600 ]; then
  run_test "1-hour gap recorded in log" "pass"
else
  run_test "1-hour gap recorded in log (got gap=$gap_logged)" "fail"
fi
rm -rf "$TEST_DIR"

echo ""
echo "========================================"
echo "Total: $((PASS + FAIL))    Pass: $PASS    Fail: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
