#!/bin/bash
# Tests for output-token-spike-detector.sh
HOOK="$(dirname "$0")/../examples/output-token-spike-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-output-spike-test.XXXXXX"
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

echo "Testing output-token-spike-detector.sh"
echo "======================================="

# Test 1: empty payload, no transcript → silent exit 0, no log entry
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read"}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "empty payload, no transcript → silent exit, no log" pass
else
  run_test "empty payload, no transcript → silent exit, no log (exit=$EXIT, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi
rm -rf "$TEST_DIR"

# Test 2: tool_response usage present → log written
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":3000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"out_tokens":3000' "$LOG"; then
  run_test "tool_response usage → log entry written" pass
else
  run_test "tool_response usage → log entry written" fail
fi
rm -rf "$TEST_DIR"

# Test 3: transcript_path fallback works
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
TRANSCRIPT="$TEST_DIR/session.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"hello"}}
{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"output_tokens":5500}}}
EOF
echo "{\"session_id\":\"s2\",\"tool_name\":\"Read\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"out_tokens":5500' "$LOG"; then
  run_test "transcript fallback → log entry from last assistant turn" pass
else
  run_test "transcript fallback → log entry from last assistant turn" fail
fi
rm -rf "$TEST_DIR"

# Test 4: zero output_tokens → no log entry, exit 0
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":0}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "zero output_tokens → no log entry" pass
else
  run_test "zero output_tokens → no log entry" fail
fi
rm -rf "$TEST_DIR"

# Test 5: non-numeric output_tokens → silent skip
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":"abc"}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "non-numeric output_tokens → silent skip" pass
else
  run_test "non-numeric output_tokens → silent skip" fail
fi
rm -rf "$TEST_DIR"

# Test 6: below MIN_HISTORY → no alert even with huge value
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for v in 3000 3000 3000 3000 3000; do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":$v}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":50000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "below MIN_HISTORY → no alert even at huge spike" pass
else
  run_test "below MIN_HISTORY → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 7: above MIN_HISTORY, within threshold → no alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":3000}" >> "$LOG"
done
# 6000 = 2x — under default 3x threshold
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":6000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_THRESHOLD=3.0 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "above MIN_HISTORY, within threshold → no alert" pass
else
  run_test "above MIN_HISTORY, within threshold → no alert (got: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 8: above MIN_HISTORY, above threshold AND above floor → alert emitted
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
# 46000 = 9.2x mean of 5000, well above 3x and above 10000 floor
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":46000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_THRESHOLD=3.0 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE:.*output_tokens=46000.*above'; then
  run_test "above MIN_HISTORY, above threshold, above floor → alert emitted" pass
else
  run_test "alert emitted (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 9: above threshold ratio BUT below floor → no alert (noise suppression)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":500}" >> "$LOG"
done
# 2500 = 5x mean of 500, exceeds 3x threshold but under 10000 floor → must not alert
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":2500}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_THRESHOLD=3.0 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "above threshold ratio but below floor → no alert (noise suppression)" pass
else
  run_test "below floor suppression (got: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 10: SILENT=1 suppresses stderr even when threshold and floor both exceeded
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":80000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_FLOOR=10000 CC_OUTPUT_SPIKE_SILENT=1 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "SILENT=1 suppresses stderr but logs anyway" pass
else
  run_test "SILENT=1 suppresses stderr (got: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 11: alert references Cluster 23 / #64153
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":46000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q '#64153'; then
  run_test "alert references upstream issue #64153" pass
else
  run_test "alert references #64153 (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 12: alert mentions the Opus 4.7 mitigation path
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":46000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'claude-opus-4-7'; then
  run_test "alert mentions Opus 4.7 fallback path" pass
else
  run_test "alert mentions Opus 4.7 (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 13: custom threshold takes effect (very strict)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
# 11000 = 2.2x — under default 3x but should trigger at threshold 2.0
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":11000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_THRESHOLD=2.0 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE'; then
  run_test "custom threshold (2.0) triggers at 2.2x deviation" pass
else
  run_test "custom threshold (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 14: custom FLOOR takes effect (lower floor catches smaller spikes)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":500}" >> "$LOG"
done
# 2500 = 5x mean of 500, above 3x threshold AND above lower floor of 1000
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":2500}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_THRESHOLD=3.0 CC_OUTPUT_SPIKE_FLOOR=1000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE'; then
  run_test "custom FLOOR (1000) allows alert below default floor" pass
else
  run_test "custom FLOOR (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 15: missing transcript file → graceful exit (no error)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read","transcript_path":"/nonexistent/path.jsonl"}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "missing transcript → graceful exit 0" pass
else
  run_test "missing transcript → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 16: invalid JSON input → graceful exit
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo 'not json at all' | CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "invalid JSON input → graceful exit 0" pass
else
  run_test "invalid JSON input → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 17: log path is created if directory doesn't exist
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/nested/dir/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":3000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ]; then
  run_test "log path with nested dir is auto-created" pass
else
  run_test "log path with nested dir is auto-created" fail
fi
rm -rf "$TEST_DIR"

# Test 18: percentage in alert is calculated correctly
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
# 40000 = 8x = +700%
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"output_tokens":40000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_THRESHOLD=3.0 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -qE '700% above'; then
  run_test "percentage calculation: 40000 vs 5000 → 700% above" pass
else
  run_test "percentage calculation: 40000 vs 5000 → 700% above (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 19: model name from tool_response is captured in log
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"model":"claude-opus-4-8","usage":{"output_tokens":3000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" bash "$HOOK" 2>/dev/null
if grep -q '"model":"claude-opus-4-8"' "$LOG"; then
  run_test "model name captured in log from tool_response" pass
else
  run_test "model name captured (log: $(cat "$LOG" 2>/dev/null))" fail
fi
rm -rf "$TEST_DIR"

# Test 20: alert text includes the model name from log
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/spike.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-31T00:00:00Z\",\"session\":\"seed\",\"model\":\"claude-opus-4-8\",\"out_tokens\":5000}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"model":"claude-opus-4-8","usage":{"output_tokens":46000}}}' | \
  CC_OUTPUT_SPIKE_LOG="$LOG" CC_OUTPUT_SPIKE_MIN_HISTORY=20 CC_OUTPUT_SPIKE_FLOOR=10000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'model=claude-opus-4-8'; then
  run_test "alert text shows current model" pass
else
  run_test "alert text shows model (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
