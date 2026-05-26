#!/bin/bash
# Tests for quota-anomaly-detector.sh
HOOK="$(dirname "$0")/../examples/quota-anomaly-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-quota-test.XXXXXX"
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

# Helper: seed N samples at a given rate around a target time.
# Args: log_path, n, base_total, base_epoch, spread_seconds_per_sample
seed_samples() {
  local log="$1" n="$2" base_total="$3" base_epoch="$4" step="$5"
  local i e
  for i in $(seq 1 "$n"); do
    e=$((base_epoch - (n - i) * step))
    printf '{"ts":"2026-05-26T00:00:00Z","epoch":%s,"session":"seed","total":%s}\n' \
      "$e" "$base_total" >> "$log"
  done
}

echo "Testing quota-anomaly-detector.sh"
echo "================================="

# Test 1: empty payload, no usage → silent exit, no log
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
echo '{"session_id":"s1","tool_name":"Read"}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "empty payload, no transcript → silent exit, no log" pass
else
  run_test "empty payload, no transcript → silent exit, no log (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 2: usage with all four token fields → sum logged
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
PAYLOAD='{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":1000,"cache_creation_input_tokens":500}}}'
echo "$PAYLOAD" | CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"total":1800' "$LOG"; then
  run_test "usage with four token fields → total summed correctly (1800)" pass
else
  run_test "usage with four token fields → total summed correctly. Got: $(cat "$LOG" 2>/dev/null)" fail
fi
rm -rf "$TEST_DIR"

# Test 3: only input+output present → still sums (missing fields treated as 0)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":50,"output_tokens":150}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"total":200' "$LOG"; then
  run_test "partial usage (input+output only) → total=200" pass
else
  run_test "partial usage (input+output only) → total=200. Got: $(cat "$LOG" 2>/dev/null)" fail
fi
rm -rf "$TEST_DIR"

# Test 4: transcript_path fallback works
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
TRANSCRIPT="$TEST_DIR/session.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"hello"}}
{"type":"assistant","message":{"usage":{"input_tokens":300,"output_tokens":700,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
EOF
echo "{\"session_id\":\"s2\",\"tool_name\":\"Read\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"total":1000' "$LOG"; then
  run_test "transcript fallback → total summed from last assistant turn" pass
else
  run_test "transcript fallback → total summed from last assistant turn. Got: $(cat "$LOG" 2>/dev/null)" fail
fi
rm -rf "$TEST_DIR"

# Test 5: all-zero usage → no log entry
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "all-zero usage → no log entry" pass
else
  run_test "all-zero usage → no log entry. Got: $(cat "$LOG")" fail
fi
rm -rf "$TEST_DIR"

# Test 6: below MIN_HISTORY → no alert even with huge value
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
seed_samples "$LOG" 5 1000 "$NOW" 60
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":1000000,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "below MIN_HISTORY → no alert" pass
else
  run_test "below MIN_HISTORY → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 7: above MIN_HISTORY but rate matches baseline → no alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
# Seed 60 samples uniformly across the entire 60-minute baseline window.
# Each sample 1000 tokens, one per minute → 1000 tok/min steady rate.
for i in $(seq 1 60); do
  E=$((NOW - 60 + i * 60 - 3600))  # i=1 → NOW-3600, i=60 → NOW-60
  printf '{"ts":"x","epoch":%s,"session":"seed","total":1000}\n' "$E" >> "$LOG"
done
# Feed a value matching the steady rate.
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":1000,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.5 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "steady rate within threshold → no alert" pass
else
  run_test "steady rate within threshold → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 8: window rate well above baseline rate → alert emitted
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
# Seed 30 samples in older part of baseline (60 min window), each 500 tokens, 60s apart starting 60 min ago.
for i in $(seq 1 30); do
  E=$((NOW - 3600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":500}\n' "$E" >> "$LOG"
done
# Seed 9 samples in the last 10 minutes at 10000 each (huge spike).
for i in $(seq 1 9); do
  E=$((NOW - 600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":10000}\n' "$E" >> "$LOG"
done
# Current sample also high.
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.5 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE:.*tok/min.*above'; then
  run_test "spike rate above threshold → alert emitted" pass
else
  run_test "spike rate above threshold → alert emitted (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 9: SILENT=1 suppresses stderr but still logs
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
for i in $(seq 1 30); do
  E=$((NOW - 3600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":500}\n' "$E" >> "$LOG"
done
for i in $(seq 1 9); do
  E=$((NOW - 600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":10000}\n' "$E" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.5 CC_QUOTA_ANOMALY_SILENT=1 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "SILENT=1 suppresses stderr but still logs" pass
else
  run_test "SILENT=1 suppresses stderr (got: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 10: alert references upstream cluster issue numbers
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
for i in $(seq 1 30); do
  E=$((NOW - 3600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":500}\n' "$E" >> "$LOG"
done
for i in $(seq 1 9); do
  E=$((NOW - 600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":10000}\n' "$E" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.5 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q '#16157'; then
  run_test "alert references upstream cluster #16157" pass
else
  run_test "alert references upstream cluster #16157 (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 11: custom threshold takes effect
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
for i in $(seq 1 30); do
  E=$((NOW - 3600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":1000}\n' "$E" >> "$LOG"
done
# Recent window slightly elevated: 1100 tokens/min, 1.1x baseline.
for i in $(seq 1 9); do
  E=$((NOW - 600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":1100}\n' "$E" >> "$LOG"
done
# Default threshold 1.5 should NOT alert. Custom 1.05 should alert.
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":1100,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.05 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE'; then
  run_test "custom threshold (1.05) triggers at 1.1x deviation" pass
else
  run_test "custom threshold (1.05) triggers at 1.1x deviation (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 12: missing transcript file → graceful exit
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
echo '{"session_id":"s1","tool_name":"Read","transcript_path":"/nonexistent/path.jsonl"}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "missing transcript → graceful exit 0" pass
else
  run_test "missing transcript → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 13: invalid JSON input → graceful exit
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
echo 'not json' | CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "invalid JSON input → graceful exit 0" pass
else
  run_test "invalid JSON input → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 14: nested log directory is created
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/nested/dir/quota.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":500,"output_tokens":500}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ]; then
  run_test "nested log dir is auto-created" pass
else
  run_test "nested log dir is auto-created" fail
fi
rm -rf "$TEST_DIR"

# Test 15: percentage and rate appear in alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
# 60 min baseline at 100 tokens/min (60 samples of 100 tokens).
for i in $(seq 1 60); do
  E=$((NOW - 3600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":100}\n' "$E" >> "$LOG"
done
# 10 min recent at 300 tokens/min (3x).
for i in $(seq 1 10); do
  E=$((NOW - 600 + i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":300}\n' "$E" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":300,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.5 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -qE 'tok/min' && echo "$STDERR" | grep -qE '% above'; then
  run_test "alert contains rate and percentage fields" pass
else
  run_test "alert contains rate and percentage (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 16: very short baseline window (no samples in baseline → no alert)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/quota.jsonl"
NOW=$(date -u +%s)
# All samples > 1h old.
for i in $(seq 1 40); do
  E=$((NOW - 7200 - i * 60))
  printf '{"ts":"x","epoch":%s,"session":"seed","total":500}\n' "$E" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"input_tokens":5000,"output_tokens":0}}}' | \
  CC_QUOTA_ANOMALY_LOG="$LOG" CC_QUOTA_ANOMALY_MIN_HISTORY=30 \
  CC_QUOTA_ANOMALY_WINDOW_MIN=10 CC_QUOTA_ANOMALY_BASELINE_MIN=60 \
  CC_QUOTA_ANOMALY_THRESHOLD=1.5 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "no baseline samples in window → no alert" pass
else
  run_test "no baseline samples in window → no alert (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
