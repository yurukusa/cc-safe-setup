#!/bin/bash
# Tests for cache-creation-drift-detector.sh
HOOK="$(dirname "$0")/../examples/cache-creation-drift-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-drift-test.XXXXXX"
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

echo "Testing cache-creation-drift-detector.sh"
echo "========================================"

# Test 1: empty payload, no transcript → silent exit 0, no log entry
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
echo '{"session_id":"s1","tool_name":"Read"}' | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "empty payload, no transcript → silent exit, no log" pass
else
  run_test "empty payload, no transcript → silent exit, no log (exit=$EXIT, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi
rm -rf "$TEST_DIR"

# Test 2: tool_response usage present → log written
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":50000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"cc_tokens":50000' "$LOG"; then
  run_test "tool_response usage → log entry written" pass
else
  run_test "tool_response usage → log entry written" fail
fi
rm -rf "$TEST_DIR"

# Test 3: transcript_path fallback works
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
TRANSCRIPT="$TEST_DIR/session.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"hello"}}
{"type":"assistant","message":{"usage":{"cache_creation_input_tokens":42000}}}
EOF
echo "{\"session_id\":\"s2\",\"tool_name\":\"Read\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"cc_tokens":42000' "$LOG"; then
  run_test "transcript fallback → log entry from last assistant turn" pass
else
  run_test "transcript fallback → log entry from last assistant turn" fail
fi
rm -rf "$TEST_DIR"

# Test 4: zero cc_tokens → no log entry, exit 0
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":0}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "zero cc_tokens → no log entry" pass
else
  run_test "zero cc_tokens → no log entry" fail
fi
rm -rf "$TEST_DIR"

# Test 5: non-numeric cc_tokens → silent skip
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":"abc"}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "non-numeric cc_tokens → silent skip" pass
else
  run_test "non-numeric cc_tokens → silent skip" fail
fi
rm -rf "$TEST_DIR"

# Test 6: below MIN_HISTORY → no alert even with huge value
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
# Pre-seed with 5 samples (below default min 20)
for v in 50000 50000 50000 50000 50000; do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":$v}" >> "$LOG"
done
# Now feed a 10x value
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":500000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "below MIN_HISTORY → no alert even at 10x" pass
else
  run_test "below MIN_HISTORY → no alert even at 10x (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 7: above MIN_HISTORY, within threshold → no alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
# Pre-seed with 25 samples around 50000
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":50000}" >> "$LOG"
done
# Feed a slightly elevated value (still under 1.25x threshold)
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":55000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 CC_CACHE_DRIFT_THRESHOLD=1.25 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "above MIN_HISTORY, within threshold → no alert" pass
else
  run_test "above MIN_HISTORY, within threshold → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 8: above MIN_HISTORY, above threshold → alert emitted
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":50000}" >> "$LOG"
done
# 70000 vs 50000 mean = 1.4x — above default 1.25 threshold
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":70000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 CC_CACHE_DRIFT_THRESHOLD=1.25 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE:.*cache_creation_input_tokens=70000.*above'; then
  run_test "above MIN_HISTORY, above threshold → alert emitted" pass
else
  run_test "above MIN_HISTORY, above threshold → alert emitted (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 9: SILENT=1 suppresses stderr even when threshold exceeded
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":50000}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":100000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 CC_CACHE_DRIFT_SILENT=1 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "SILENT=1 suppresses stderr but logs anyway" pass
else
  run_test "SILENT=1 suppresses stderr (got: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 10: alert references upstream issue #46917
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":50000}" >> "$LOG"
done
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":80000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 CC_CACHE_DRIFT_THRESHOLD=1.25 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q '#46917'; then
  run_test "alert references upstream issue #46917" pass
else
  run_test "alert references upstream issue #46917 (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 11: custom threshold takes effect (very strict, alerts at small deviation)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":50000}" >> "$LOG"
done
# 53000 = 1.06x — under default 1.25 but should trigger at threshold 1.05
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":53000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 CC_CACHE_DRIFT_THRESHOLD=1.05 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE'; then
  run_test "custom threshold (1.05) triggers at 1.06x deviation" pass
else
  run_test "custom threshold (1.05) triggers at 1.06x deviation (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 12: missing transcript file → graceful exit (no error)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
echo '{"session_id":"s1","tool_name":"Read","transcript_path":"/nonexistent/path.jsonl"}' | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "missing transcript → graceful exit 0" pass
else
  run_test "missing transcript → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 13: invalid JSON input → graceful exit
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
echo 'not json at all' | CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "invalid JSON input → graceful exit 0" pass
else
  run_test "invalid JSON input → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 14: log path is created if directory doesn't exist
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/nested/dir/drift.jsonl"
echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":50000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ]; then
  run_test "log path with nested dir is auto-created" pass
else
  run_test "log path with nested dir is auto-created" fail
fi
rm -rf "$TEST_DIR"

# Test 15: percentage in alert is calculated correctly
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/drift.jsonl"
for i in $(seq 1 25); do
  echo "{\"ts\":\"2026-05-26T00:00:00Z\",\"session\":\"seed\",\"cc_tokens\":50000}" >> "$LOG"
done
# 75000 = 1.5x = +50%
STDERR=$(echo '{"session_id":"s1","tool_name":"Read","tool_response":{"usage":{"cache_creation_input_tokens":75000}}}' | \
  CC_CACHE_DRIFT_LOG="$LOG" CC_CACHE_DRIFT_MIN_HISTORY=20 CC_CACHE_DRIFT_THRESHOLD=1.25 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -qE '50% above'; then
  run_test "percentage calculation: 75000 vs 50000 → 50% above" pass
else
  run_test "percentage calculation: 75000 vs 50000 → 50% above (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
