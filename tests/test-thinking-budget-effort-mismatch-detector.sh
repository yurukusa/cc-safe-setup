#!/bin/bash
# Tests for thinking-budget-effort-mismatch-detector.sh
HOOK="$(dirname "$0")/../examples/thinking-budget-effort-mismatch-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-thinking-budget-test.XXXXXX"
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

echo "Testing thinking-budget-effort-mismatch-detector.sh"
echo "==================================================="

# Test 1: empty payload, no transcript → silent exit 0, no log
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo '{"session_id":"s1","tool_name":"Read"}' | \
  CC_THINKING_BUDGET_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "empty payload → silent exit, no log" pass
else
  run_test "empty payload → silent exit, no log" fail
fi
rm -rf "$TEST_DIR"

# Test 2: medium tier, under threshold (20000 < 30000) → no log, no stderr
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s1","tool_response":{"usage":{"output_tokens":20000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ ! -f "$LOG" ] && [ ! -s "$STDERR_FILE" ]; then
  run_test "medium tier, 20k under 30k → no log, no stderr" pass
else
  run_test "medium tier, 20k under 30k → no log, no stderr" fail
fi
rm -rf "$TEST_DIR"

# Test 3: medium tier, over threshold (46433 > 30000) → log + stderr
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s1","tool_response":{"usage":{"output_tokens":46433}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && grep -q '"out_tokens":46433' "$LOG" && \
   grep -q '"tier":"medium"' "$LOG" && \
   grep -q "Cluster 23" "$STDERR_FILE"; then
  run_test "medium tier, 46k over 30k → log + stderr (anchor case)" pass
else
  run_test "medium tier, 46k over 30k → log + stderr (anchor case)" fail
fi
rm -rf "$TEST_DIR"

# Test 4: low tier, 15000 over 10000 default → alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s2","tool_response":{"usage":{"output_tokens":15000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=low \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && grep -q '"tier":"low"' "$LOG" && \
   grep -q '"threshold":10000' "$LOG"; then
  run_test "low tier, 15k over 10k → alert with low threshold" pass
else
  run_test "low tier, 15k over 10k → alert with low threshold" fail
fi
rm -rf "$TEST_DIR"

# Test 5: high tier, 70000 under 80000 default → no alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s3","tool_response":{"usage":{"output_tokens":70000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=high \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ ! -f "$LOG" ] && [ ! -s "$STDERR_FILE" ]; then
  run_test "high tier, 70k under 80k → no alert" pass
else
  run_test "high tier, 70k under 80k → no alert" fail
fi
rm -rf "$TEST_DIR"

# Test 6: high tier, 90000 over 80000 default → alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s4","tool_response":{"usage":{"output_tokens":90000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=high \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && grep -q '"tier":"high"' "$LOG"; then
  run_test "high tier, 90k over 80k → alert" pass
else
  run_test "high tier, 90k over 80k → alert" fail
fi
rm -rf "$TEST_DIR"

# Test 7: default tier (no env) → medium
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo '{"session_id":"s5","tool_response":{"usage":{"output_tokens":35000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"tier":"medium"' "$LOG"; then
  run_test "default tier (env unset) → medium" pass
else
  run_test "default tier (env unset) → medium" fail
fi
rm -rf "$TEST_DIR"

# Test 8: unrecognized tier → falls back to medium
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo '{"session_id":"s6","tool_response":{"usage":{"output_tokens":35000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=bogus \
  bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"tier":"medium"' "$LOG"; then
  run_test "unrecognized tier → medium fallback" pass
else
  run_test "unrecognized tier → medium fallback" fail
fi
rm -rf "$TEST_DIR"

# Test 9: CC_THINKING_BUDGET_DISABLE=1 → silent exit no matter the value
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s7","tool_response":{"usage":{"output_tokens":200000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_BUDGET_DISABLE=1 \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ ! -f "$LOG" ] && [ ! -s "$STDERR_FILE" ]; then
  run_test "DISABLE=1 → no log, no stderr even for huge value" pass
else
  run_test "DISABLE=1 → no log, no stderr even for huge value" fail
fi
rm -rf "$TEST_DIR"

# Test 10: CC_THINKING_BUDGET_SILENT=1 → log but no stderr
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s8","tool_response":{"usage":{"output_tokens":50000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_BUDGET_SILENT=1 \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && [ ! -s "$STDERR_FILE" ]; then
  run_test "SILENT=1 → log written, no stderr" pass
else
  run_test "SILENT=1 → log written, no stderr" fail
fi
rm -rf "$TEST_DIR"

# Test 11: custom medium threshold via env var
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s9","tool_response":{"usage":{"output_tokens":35000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  CC_THINKING_BUDGET_MEDIUM_MAX=40000 \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ ! -f "$LOG" ] && [ ! -s "$STDERR_FILE" ]; then
  run_test "custom medium threshold 40k → 35k under, no alert" pass
else
  run_test "custom medium threshold 40k → 35k under, no alert" fail
fi
rm -rf "$TEST_DIR"

# Test 12: transcript fallback for output_tokens
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
TRANSCRIPT="$TEST_DIR/session.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"hi"}}
{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"output_tokens":42000}}}
EOF
STDERR_FILE="$TEST_DIR/stderr"
echo "{\"session_id\":\"s10\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && grep -q '"out_tokens":42000' "$LOG" && \
   grep -q '"model":"claude-opus-4-8"' "$LOG"; then
  run_test "transcript fallback → reads output_tokens and model" pass
else
  run_test "transcript fallback → reads output_tokens and model" fail
fi
rm -rf "$TEST_DIR"

# Test 13: zero output_tokens → no log, no alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo '{"session_id":"s11","tool_response":{"usage":{"output_tokens":0}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=low \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "zero output_tokens → no log" pass
else
  run_test "zero output_tokens → no log" fail
fi
rm -rf "$TEST_DIR"

# Test 14: non-numeric output_tokens → silent skip
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo '{"session_id":"s12","tool_response":{"usage":{"output_tokens":"abc"}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "non-numeric output_tokens → silent skip" pass
else
  run_test "non-numeric output_tokens → silent skip" fail
fi
rm -rf "$TEST_DIR"

# Test 15: exactly at threshold → no alert (le comparison)
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s13","tool_response":{"usage":{"output_tokens":30000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ ! -f "$LOG" ] && [ ! -s "$STDERR_FILE" ]; then
  run_test "exactly at threshold (30000=30000) → no alert" pass
else
  run_test "exactly at threshold (30000=30000) → no alert" fail
fi
rm -rf "$TEST_DIR"

# Test 16: one over threshold → alert
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s14","tool_response":{"usage":{"output_tokens":30001}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && grep -q "Cluster 23" "$STDERR_FILE"; then
  run_test "one over threshold (30001>30000) → alert" pass
else
  run_test "one over threshold (30001>30000) → alert" fail
fi
rm -rf "$TEST_DIR"

# Test 17: corrupted JSON input → exit 0, no crash
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo 'not json {{{' | \
  CC_THINKING_BUDGET_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "corrupted JSON → exit 0, no crash, no log" pass
else
  run_test "corrupted JSON → exit 0, no crash, no log (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 18: stderr message includes the Opus 4.7 mitigation
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s15","tool_response":{"usage":{"output_tokens":50000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if grep -q "claude-opus-4-7" "$STDERR_FILE"; then
  run_test "stderr includes Opus 4.7 mitigation path" pass
else
  run_test "stderr includes Opus 4.7 mitigation path" fail
fi
rm -rf "$TEST_DIR"

# Test 19: stderr message includes anchor issue reference
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s16","tool_response":{"usage":{"output_tokens":50000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if grep -q "#64153" "$STDERR_FILE"; then
  run_test "stderr includes anchor issue #64153" pass
else
  run_test "stderr includes anchor issue #64153" fail
fi
rm -rf "$TEST_DIR"

# Test 20: overshoot calculation included in stderr
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
echo '{"session_id":"s17","tool_response":{"usage":{"output_tokens":50000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>"$STDERR_FILE"
if grep -q "overshoot 20000" "$STDERR_FILE"; then
  run_test "stderr includes overshoot value (50k - 30k = 20k)" pass
else
  run_test "stderr includes overshoot value (50k - 30k = 20k)" fail
fi
rm -rf "$TEST_DIR"

# Test 21: JSON log entry includes timestamp in ISO 8601
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/budget.jsonl"
echo '{"session_id":"s18","tool_response":{"usage":{"output_tokens":50000}}}' | \
  CC_THINKING_BUDGET_LOG="$LOG" CC_THINKING_EFFORT_TIER=medium \
  bash "$HOOK" 2>/dev/null
if grep -qE '"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$LOG"; then
  run_test "log entry includes ISO 8601 UTC timestamp" pass
else
  run_test "log entry includes ISO 8601 UTC timestamp" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
