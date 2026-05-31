#!/bin/bash
# Tests for tool-result-correlation-checker.sh
HOOK="$(dirname "$0")/../examples/tool-result-correlation-checker.sh"
PASS=0
FAIL=0

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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
STATE="$TMPDIR/state"
TRANSCRIPT="$TMPDIR/transcript.jsonl"

reset_state() {
  rm -rf "$STATE"
  mkdir -p "$STATE"
  : > "$TRANSCRIPT"
  unset CC_TOOL_CORRELATION_DISABLE
  unset CC_TOOL_CORRELATION_QUIET
  unset CC_TOOL_CORRELATION_THRESHOLD
  unset CC_TOOL_CORRELATION_WINDOW_SEC
}

# Helper: build assistant turn with N tool_use blocks (ids id_1 .. id_N)
make_assistant_turn() {
  local count="$1"
  local blocks=""
  for i in $(seq 1 "$count"); do
    blocks="${blocks}{\"type\":\"tool_use\",\"id\":\"id_${i}\",\"name\":\"Bash\",\"input\":{}}"
    [ "$i" -lt "$count" ] && blocks="${blocks},"
  done
  printf '{"type":"assistant","message":{"content":[%s]}}\n' "$blocks"
}

# Helper: build user turn with tool_result blocks for given ids
make_user_turn() {
  local ids="$1"  # space-separated ids
  local blocks=""
  local first=1
  for id in $ids; do
    [ "$first" = "0" ] && blocks="${blocks},"
    blocks="${blocks}{\"type\":\"tool_result\",\"tool_use_id\":\"${id}\",\"content\":\"ok\"}"
    first=0
  done
  printf '{"type":"user","message":{"content":[%s]}}\n' "$blocks"
}

make_input() {
  printf '{"transcript_path":"%s","tool_response":"ok"}' "$TRANSCRIPT"
}

echo "Testing tool-result-correlation-checker.sh"
echo "==========================================="

# Test 1: DISABLE=1 silences entirely
reset_state
make_assistant_turn 3 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" CC_TOOL_CORRELATION_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences entirely" pass
else
  run_test "DISABLE=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 silences entirely
reset_state
make_assistant_turn 3 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" CC_TOOL_CORRELATION_QUIET=1 bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "QUIET=1 silences entirely" pass
else
  run_test "QUIET=1 (out_len=${#OUT})" fail
fi

# Test 3: perfect correlation produces no output
reset_state
make_assistant_turn 3 >> "$TRANSCRIPT"
make_user_turn "id_1 id_2 id_3" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "perfect correlation produces no output" pass
else
  run_test "perfect correlation (got output: ${OUT:0:80})" fail
fi

# Test 4: orphan result (no matching use) triggers warning
reset_state
make_assistant_turn 2 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "correlation mismatch"; then
  run_test "orphan result triggers warning" pass
else
  run_test "orphan result (out=${OUT:0:80})" fail
fi

# Test 5: duplicate result ids trigger warning
reset_state
make_assistant_turn 3 >> "$TRANSCRIPT"
make_user_turn "id_1 id_1 id_3" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "correlation mismatch"; then
  run_test "duplicate result ids trigger warning" pass
else
  run_test "duplicate result ids (out=${OUT:0:80})" fail
fi

# Test 6: missing result (use without result) does NOT trigger warning
# Rationale: missing results are common during in-flight batches; we only
# warn on orphan/duplicate which are unambiguous misrouting signals
reset_state
make_assistant_turn 5 >> "$TRANSCRIPT"
make_user_turn "id_1 id_2 id_3" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "missing result does NOT warn (in-flight is normal)" pass
else
  run_test "missing result false positive (out=${OUT:0:80})" fail
fi

# Test 7: empty transcript path produces no output
reset_state
INPUT='{"tool_response":"ok"}'
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "empty transcript path is silent" pass
else
  run_test "empty transcript path (out=${OUT:0:80})" fail
fi

# Test 8: non-existent transcript file is silent
reset_state
INPUT='{"transcript_path":"/nonexistent/path.jsonl","tool_response":"ok"}'
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "non-existent transcript is silent" pass
else
  run_test "non-existent transcript (out=${OUT:0:80})" fail
fi

# Test 9: malformed JSON in transcript is silent
reset_state
echo "this is not json" > "$TRANSCRIPT"
echo "neither is this" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "malformed JSON in transcript is silent" pass
else
  run_test "malformed JSON (out=${OUT:0:80})" fail
fi

# Test 10: THRESHOLD=2 requires 2 events to warn
reset_state
make_assistant_turn 2 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
# First mismatch — should be silent with threshold 2
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" CC_TOOL_CORRELATION_THRESHOLD=2 bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "THRESHOLD=2 silent on first event" pass
else
  run_test "THRESHOLD=2 first event (out=${OUT:0:80})" fail
fi

# Second mismatch — should warn
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" CC_TOOL_CORRELATION_THRESHOLD=2 bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "correlation mismatch"; then
  run_test "THRESHOLD=2 warns on second event" pass
else
  run_test "THRESHOLD=2 second event (out=${OUT:0:80})" fail
fi

# Test 11: rolling window pruning (old events fall off)
reset_state
make_assistant_turn 2 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
# Inject an old event manually (60s in the past with window=1s = old)
OLD_TS=$(( $(date +%s) - 1000 ))
mkdir -p "$STATE"
echo "$OLD_TS" > "$STATE/events.log"
# Fire with WINDOW_SEC=1 and THRESHOLD=2 — the old event should be pruned,
# the new event becomes the first within window, so no warning
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" CC_TOOL_CORRELATION_WINDOW_SEC=1 CC_TOOL_CORRELATION_THRESHOLD=2 bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "rolling window prunes old events" pass
else
  run_test "window pruning (out=${OUT:0:80})" fail
fi

# Test 12: assistant turn with no tool_use blocks is silent
reset_state
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"just text"}]}}' >> "$TRANSCRIPT"
make_user_turn "id_1" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if [ -z "$OUT" ]; then
  run_test "no tool_use blocks is silent" pass
else
  run_test "no tool_use (out=${OUT:0:80})" fail
fi

# Test 13: orphan result count is reported in warning
reset_state
make_assistant_turn 2 >> "$TRANSCRIPT"
make_user_turn "id_98 id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "Orphan results.*: 2"; then
  run_test "orphan count reported in warning" pass
else
  run_test "orphan count (out=${OUT:0:120})" fail
fi

# Test 14: warning includes operator action
reset_state
make_assistant_turn 2 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "Operator action"; then
  run_test "warning includes operator action guidance" pass
else
  run_test "operator action missing (out=${OUT:0:120})" fail
fi

# Test 15: warning includes silencer hint
reset_state
make_assistant_turn 2 >> "$TRANSCRIPT"
make_user_turn "id_99" >> "$TRANSCRIPT"
INPUT=$(make_input)
OUT=$(printf '%s' "$INPUT" | CC_TOOL_CORRELATION_STATE_DIR="$STATE" CC_TOOL_CORRELATION_TRANSCRIPT="$TRANSCRIPT" bash "$HOOK" 2>&1)
if printf '%s' "$OUT" | grep -q "CC_TOOL_CORRELATION_QUIET"; then
  run_test "warning includes silencer hint" pass
else
  run_test "silencer hint missing (out=${OUT:0:120})" fail
fi

echo ""
echo "==========================================="
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
echo "==========================================="
exit $FAIL
