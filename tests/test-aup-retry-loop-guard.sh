#!/bin/bash
# Tests for aup-retry-loop-guard.sh
HOOK="$(dirname "$0")/../examples/aup-retry-loop-guard.sh"
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
LOG="$TMPDIR/aup-block.log"
STATE="$TMPDIR/state"

log_line() {
  local seconds_ago="$1"
  local tool="$2"
  local kind="${3:-cyber-safeguards}"
  local ts
  ts=$(date -u -d "$seconds_ago seconds ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v "-${seconds_ago}S" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
  printf '%s|claude-opus-4-7|%s|%s|excerpt\n' "$ts" "$tool" "$kind" >> "$LOG"
}

reset_state() {
  rm -f "$LOG"
  rm -rf "$STATE"
  mkdir -p "$STATE"
  unset CC_AUP_RETRY_LOOP_GUARD_DISABLE
  unset CC_AUP_RETRY_LOOP_GUARD_QUIET
  unset CC_AUP_RETRY_LOOP_GUARD_THRESHOLD
  unset CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN
  unset CC_AUP_RETRY_LOOP_GUARD_TARGET
}

echo "Testing aup-retry-loop-guard.sh"
echo "================================"

# Test 1: DISABLE=1 silences
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences entirely" pass
else
  run_test "DISABLE=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 silences
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences" pass
else
  run_test "QUIET=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: Log missing → silent
reset_state
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Log missing → silent" pass
else
  run_test "Log missing (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: Log empty → silent
reset_state
: > "$LOG"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Log empty → silent" pass
else
  run_test "Log empty (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: 1 block in window (below threshold) → silent
reset_state
log_line 60 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "1 block (below threshold 3) → silent" pass
else
  run_test "1 block (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: 2 blocks in window (below threshold) → silent
reset_state
log_line 60 "Bash"; log_line 120 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "2 blocks (below threshold 3) → silent" pass
else
  run_test "2 blocks (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: 3 blocks same tool in window → advisory emitted
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "Retry-loop pattern detected"; then
  run_test "3 blocks same tool → advisory emitted" pass
else
  run_test "3 blocks same tool (exit=$EXIT, OUT: ${OUT:0:120})" fail
fi

# Test 8: Multi-tool burst → silent (not a retry loop)
reset_state
log_line 60 "Bash"; log_line 120 "Edit"; log_line 180 "Read"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Multi-tool burst → silent (not retry loop)" pass
else
  run_test "Multi-tool burst (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 9: Blocks outside window → silent (default window 5 min)
reset_state
log_line 600 "Bash"; log_line 700 "Bash"; log_line 800 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Blocks outside window → silent" pass
else
  run_test "Stale blocks (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 10: Custom THRESHOLD=2, 2 blocks same tool → advisory
reset_state
log_line 60 "Bash"; log_line 120 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_THRESHOLD=2 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "2 Usage Policy block"; then
  run_test "Custom THRESHOLD=2 → 2 blocks triggers advisory" pass
else
  run_test "Custom threshold (OUT: ${OUT:0:120})" fail
fi

# Test 11: Custom WINDOW_MIN=1, 3 blocks within 1 min → advisory
reset_state
log_line 10 "Bash"; log_line 20 "Bash"; log_line 30 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN=1 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "Retry-loop pattern detected"; then
  run_test "Custom WINDOW_MIN=1 → in-window blocks detected" pass
else
  run_test "Custom window (OUT: ${OUT:0:120})" fail
fi

# Test 12: Custom WINDOW_MIN=1, blocks span 5 min → silent
reset_state
log_line 60 "Bash"; log_line 180 "Bash"; log_line 240 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Custom WINDOW_MIN=1, blocks spread → silent" pass
else
  run_test "Spread blocks with narrow window (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 13: Custom TARGET appears in advisory
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_TARGET=claude-sonnet-4-6 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "ANTHROPIC_MODEL=claude-sonnet-4-6"; then
  run_test "Custom TARGET appears in advisory" pass
else
  run_test "Custom target (OUT: ${OUT:0:120})" fail
fi

# Test 14: Advisory mentions /exit option
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "/exit"; then
  run_test "Advisory recommends /exit cycle-break" pass
else
  run_test "/exit recommendation (OUT: ${OUT:0:120})" fail
fi

# Test 15: Advisory references issue #61664 (the central retry-loop pain)
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "61664"; then
  run_test "Advisory references issue #61664" pass
else
  run_test "Issue #61664 reference (OUT: ${OUT:0:120})" fail
fi

# Test 16: Advisory references partner hooks
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "aup-false-positive-helper" && echo "$OUT" | grep -q "aup-block-pattern-logger" && echo "$OUT" | grep -q "model-swap-suggester"; then
  run_test "Advisory references all three partner hooks" pass
else
  run_test "Partner hook references (OUT: ${OUT:0:200})" fail
fi

# Test 17: One-shot per session — second invocation silent with same SESSION_ID
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT1=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_SESSION_ID="test-session-A" bash "$HOOK" 2>&1)
OUT2=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_SESSION_ID="test-session-A" bash "$HOOK" 2>&1)
OUT3=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_SESSION_ID="test-session-B" bash "$HOOK" 2>&1)
if echo "$OUT1" | grep -q "Retry-loop pattern detected" && [ -z "$OUT2" ] && echo "$OUT3" | grep -q "Retry-loop pattern detected"; then
  run_test "One-shot per session — same session silent, different session fires" pass
else
  run_test "One-shot (OUT1_len=${#OUT1}, OUT2_len=${#OUT2}, OUT3_len=${#OUT3})" fail
fi

# Test 18: Garbage env vars fall back to defaults
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" CC_AUP_RETRY_LOOP_GUARD_THRESHOLD=abc CC_AUP_RETRY_LOOP_GUARD_WINDOW_MIN=xyz bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "Retry-loop pattern detected"; then
  run_test "Garbage env vars fall back to defaults" pass
else
  run_test "Garbage env vars (OUT: ${OUT:0:120})" fail
fi

# Test 19: Unparseable timestamps skipped
reset_state
printf 'BAD-TS|claude-opus-4-7|Bash|cyber-safeguards|excerpt\n' >> "$LOG"
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "Retry-loop pattern detected"; then
  run_test "Unparseable timestamps skipped without crash" pass
else
  run_test "Unparseable timestamps (exit=$EXIT, OUT: ${OUT:0:120})" fail
fi

# Test 20: Mix of in-window and out-of-window single-tool blocks — count only in-window
reset_state
log_line 60 "Bash"; log_line 120 "Bash"   # 2 in-window
log_line 600 "Bash"; log_line 700 "Bash"  # 2 stale (outside 5min default)
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
EXIT=$?
# Only 2 in-window blocks; threshold is 3 → silent
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Mix in/out-of-window — only in-window counted" pass
else
  run_test "Mix counting (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 21: Pattern kind reflected in advisory
reset_state
log_line 60 "Bash" "safety-guardrails"
log_line 120 "Bash" "safety-guardrails"
log_line 180 "Bash" "safety-guardrails"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "safety-guardrails"; then
  run_test "Pattern kind included in advisory" pass
else
  run_test "Pattern kind (OUT: ${OUT:0:120})" fail
fi

# Test 22: Tool name in advisory reflects log
reset_state
log_line 60 "Edit"; log_line 120 "Edit"; log_line 180 "Edit"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q 'tool "Edit"'; then
  run_test "Tool name reflected in advisory" pass
else
  run_test "Tool name reflection (OUT: ${OUT:0:120})" fail
fi

# Test 23: Hook never blocks (exit 0 across all paths)
reset_state
EXIT_CODES=""
for case in "disable" "quiet" "no-log" "empty-log" "below-thresh" "above-thresh" "multi-tool"; do
  reset_state
  case "$case" in
    "disable") OUT=$(CC_AUP_RETRY_LOOP_GUARD_DISABLE=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "quiet") OUT=$(CC_AUP_RETRY_LOOP_GUARD_QUIET=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "no-log") OUT=$(CC_AUP_BLOCK_LOG_PATH="$TMPDIR/none.log" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1); EXIT=$? ;;
    "empty-log") : > "$LOG"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1); EXIT=$? ;;
    "below-thresh") log_line 60 "Bash"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1); EXIT=$? ;;
    "above-thresh") log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1); EXIT=$? ;;
    "multi-tool") log_line 60 "Bash"; log_line 120 "Edit"; log_line 180 "Read"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks (7 paths all exit 0)" pass
else
  run_test "Exit codes (got: $EXIT_CODES)" fail
fi

# Test 24: GitHub references present
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "github.com/anthropics/claude-code/issues/60366" && echo "$OUT" | grep -q "github.com/anthropics/claude-code/issues/61664"; then
  run_test "Advisory includes both anchor issue references" pass
else
  run_test "Issue references (OUT: ${OUT:0:200})" fail
fi

# Test 25: 5 blocks same tool still fires (count uses actual not threshold)
reset_state
for s in 30 60 90 120 180; do log_line "$s" "Bash"; done
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "5 Usage Policy block"; then
  run_test "Higher counts reported correctly (5 blocks)" pass
else
  run_test "5 blocks count (OUT: ${OUT:0:120})" fail
fi

# Test 26: QUIET escape hatch documented
reset_state
log_line 60 "Bash"; log_line 120 "Bash"; log_line 180 "Bash"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_RETRY_LOOP_GUARD_STATE_DIR="$STATE" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_AUP_RETRY_LOOP_GUARD_QUIET=1"; then
  run_test "Advisory documents QUIET escape hatch" pass
else
  run_test "QUIET escape hatch (OUT: ${OUT:0:120})" fail
fi

echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
