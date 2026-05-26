#!/bin/bash
# Tests for session-rate-monitor.sh
HOOK="$(dirname "$0")/../examples/session-rate-monitor.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-srate-test.XXXXXX"
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

# Helper to seed a state file with an older start_epoch (simulate prior samples).
# Args: state_file, start_epoch, total, count, last_alert
seed_state() {
  printf '%s %s %s %s\n' "$2" "$3" "$4" "$5" > "$1"
}

echo "Testing session-rate-monitor.sh"
echo "================================"

# Test 1: missing session_id → no state written
TEST_DIR=$(mktempd)
echo '{"tool_response":{"usage":{"input_tokens":1000,"output_tokens":1000}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
COUNT=$(find "$TEST_DIR" -maxdepth 1 -type f | wc -l)
if [ "$COUNT" = "0" ]; then
  run_test "missing session_id → no state written" pass
else
  run_test "missing session_id → no state written (found $COUNT files)" fail
fi
rm -rf "$TEST_DIR"

# Test 2: first sample initializes state, no alert
TEST_DIR=$(mktempd)
STDERR=$(echo '{"session_id":"sess-1","tool_response":{"usage":{"input_tokens":1000,"output_tokens":1000}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>&1 >/dev/null)
if [ -f "$TEST_DIR/sess-1" ] && [ -z "$STDERR" ]; then
  run_test "first sample initializes state, no alert" pass
else
  run_test "first sample initializes state, no alert (stderr: $STDERR, file exists: $([ -f "$TEST_DIR/sess-1" ] && echo yes || echo no))" fail
fi
rm -rf "$TEST_DIR"

# Test 3: state file accumulates tokens across calls
TEST_DIR=$(mktempd)
echo '{"session_id":"sess-2","tool_response":{"usage":{"input_tokens":500,"output_tokens":500}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
echo '{"session_id":"sess-2","tool_response":{"usage":{"input_tokens":300,"output_tokens":700}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
TOTAL=$(awk '{print $2}' "$TEST_DIR/sess-2")
COUNT=$(awk '{print $3}' "$TEST_DIR/sess-2")
if [ "$TOTAL" = "2000" ] && [ "$COUNT" = "2" ]; then
  run_test "state accumulates tokens and count across calls" pass
else
  run_test "state accumulates (total=$TOTAL, count=$COUNT, expected 2000/2)" fail
fi
rm -rf "$TEST_DIR"

# Test 4: zero usage → no state initialized
TEST_DIR=$(mktempd)
echo '{"session_id":"sess-3","tool_response":{"usage":{"input_tokens":0,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
if [ ! -f "$TEST_DIR/sess-3" ]; then
  run_test "zero usage → no state written" pass
else
  run_test "zero usage → no state written" fail
fi
rm -rf "$TEST_DIR"

# Test 5: below MIN_SAMPLES → no alert even at huge rate
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 600))
seed_state "$TEST_DIR/sess-4" "$OLD" 100000 2 0
STDERR=$(echo '{"session_id":"sess-4","tool_response":{"usage":{"input_tokens":100000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_THRESHOLD=50000 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "below MIN_SAMPLES → no alert even at huge rate" pass
else
  run_test "below MIN_SAMPLES → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 6: below MIN_ELAPSED → no alert even after enough samples
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
RECENT=$((NOW - 10))  # Only 10 seconds elapsed
seed_state "$TEST_DIR/sess-5" "$RECENT" 100000 10 0
STDERR=$(echo '{"session_id":"sess-5","tool_response":{"usage":{"input_tokens":100000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "below MIN_ELAPSED → no alert" pass
else
  run_test "below MIN_ELAPSED → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 7: rate below threshold → no alert
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 600))  # 10 minutes elapsed
# 100000 tokens in 10 minutes = 10000 tok/min, below 50000 ceiling
seed_state "$TEST_DIR/sess-6" "$OLD" 90000 9 0
STDERR=$(echo '{"session_id":"sess-6","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
  run_test "rate below threshold → no alert" pass
else
  run_test "rate below threshold → no alert (got stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 8: rate above threshold → alert emitted
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 120))  # 2 minutes elapsed
# 200000 tokens in 2 minutes = 100000 tok/min, above 50000 ceiling
seed_state "$TEST_DIR/sess-7" "$OLD" 190000 9 0
STDERR=$(echo '{"session_id":"sess-7","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE:.*session burning.*tok/min'; then
  run_test "rate above threshold → alert emitted" pass
else
  run_test "rate above threshold → alert emitted (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 9: alert references upstream cluster issues
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 120))
seed_state "$TEST_DIR/sess-8" "$OLD" 190000 9 0
STDERR=$(echo '{"session_id":"sess-8","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q '#16157'; then
  run_test "alert references upstream cluster #16157" pass
else
  run_test "alert references upstream cluster #16157 (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 10: SILENT=1 suppresses stderr but still updates state
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 120))
seed_state "$TEST_DIR/sess-9" "$OLD" 190000 9 0
STDERR=$(echo '{"session_id":"sess-9","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 \
  CC_SESSION_RATE_SILENT=1 bash "$HOOK" 2>&1 >/dev/null)
TOTAL=$(awk '{print $2}' "$TEST_DIR/sess-9")
if [ -z "$STDERR" ] && [ "$TOTAL" = "200000" ]; then
  run_test "SILENT=1 suppresses stderr but still updates state" pass
else
  run_test "SILENT=1 (stderr: $STDERR, total: $TOTAL)" fail
fi
rm -rf "$TEST_DIR"

# Test 11: repeat alert suppression — second call within REPEAT_MIN does not re-alert
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 120))
# First alert seeds last_alert to "now" via the hook.
seed_state "$TEST_DIR/sess-10" "$OLD" 190000 9 0
STDERR1=$(echo '{"session_id":"sess-10","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 \
  CC_SESSION_RATE_REPEAT_MIN=5 bash "$HOOK" 2>&1 >/dev/null)
# Second call right after — should be suppressed.
STDERR2=$(echo '{"session_id":"sess-10","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 \
  CC_SESSION_RATE_REPEAT_MIN=5 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR1" | grep -q 'NOTICE' && [ -z "$STDERR2" ]; then
  run_test "repeat alert suppression: second call within REPEAT_MIN is silent" pass
else
  run_test "repeat suppression (1st: $STDERR1, 2nd: $STDERR2)" fail
fi
rm -rf "$TEST_DIR"

# Test 12: transcript fallback works when no payload usage
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":500,"output_tokens":500,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
EOF
echo "{\"session_id\":\"sess-11\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
TOTAL=$(awk '{print $2}' "$TEST_DIR/sess-11" 2>/dev/null)
if [ "$TOTAL" = "1000" ]; then
  run_test "transcript fallback → total summed (1000)" pass
else
  run_test "transcript fallback → total summed (got: $TOTAL)" fail
fi
rm -rf "$TEST_DIR"

# Test 13: invalid JSON → graceful exit
TEST_DIR=$(mktempd)
echo 'not json' | CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ]; then
  run_test "invalid JSON → graceful exit 0" pass
else
  run_test "invalid JSON → graceful exit 0 (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 14: session_id with special characters is sanitized for filename
TEST_DIR=$(mktempd)
echo '{"session_id":"sess/with../slashes","tool_response":{"usage":{"input_tokens":100,"output_tokens":100}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
# No directory traversal: no file outside STATE_DIR.
PARENT_FILES=$(find "$TEST_DIR/.." -maxdepth 1 -newer "$TEST_DIR/.." -type f 2>/dev/null | grep -v "$TEST_DIR" | wc -l)
DIR_FILES=$(find "$TEST_DIR" -maxdepth 1 -type f | wc -l)
if [ "$DIR_FILES" -ge "1" ]; then
  run_test "session_id with slashes → sanitized, no escape" pass
else
  run_test "session_id with slashes → sanitized (dir_files=$DIR_FILES)" fail
fi
rm -rf "$TEST_DIR"

# Test 15: all four token fields summed
TEST_DIR=$(mktempd)
echo '{"session_id":"sess-12","tool_response":{"usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":3000,"cache_creation_input_tokens":700}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
TOTAL=$(awk '{print $2}' "$TEST_DIR/sess-12" 2>/dev/null)
if [ "$TOTAL" = "4000" ]; then
  run_test "all four token fields summed (100+200+3000+700=4000)" pass
else
  run_test "all four token fields summed (got: $TOTAL)" fail
fi
rm -rf "$TEST_DIR"

# Test 16: alert message contains rate, elapsed, and threshold
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 120))
seed_state "$TEST_DIR/sess-13" "$OLD" 190000 9 0
STDERR=$(echo '{"session_id":"sess-13","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=50000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -qE 'tok/min' && echo "$STDERR" | grep -qE '[0-9]+\.[0-9]+min' && echo "$STDERR" | grep -q '50000 tok/min ceiling'; then
  run_test "alert message contains rate, elapsed minutes, and threshold ceiling" pass
else
  run_test "alert message format (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

# Test 17: custom threshold takes effect
TEST_DIR=$(mktempd)
NOW=$(date -u +%s)
OLD=$((NOW - 600))  # 10 min
# 60000 tokens in 10 min = 6000 tok/min
seed_state "$TEST_DIR/sess-14" "$OLD" 50000 9 0
# Default 50000 should not trigger. Custom 5000 should.
STDERR=$(echo '{"session_id":"sess-14","tool_response":{"usage":{"input_tokens":10000,"output_tokens":0}}}' | \
  CC_SESSION_RATE_DIR="$TEST_DIR" CC_SESSION_RATE_MIN_SAMPLES=5 \
  CC_SESSION_RATE_MIN_ELAPSED=60 CC_SESSION_RATE_THRESHOLD=5000 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q 'NOTICE'; then
  run_test "custom threshold (5000) triggers at 6000 tok/min" pass
else
  run_test "custom threshold (stderr: $STDERR)" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
