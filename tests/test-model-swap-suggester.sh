#!/bin/bash
# Tests for model-swap-suggester.sh
HOOK="$(dirname "$0")/../examples/model-swap-suggester.sh"
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

# Helper: write a log line with a timestamp offset (seconds) relative to now.
# Positive offset = into the past. Schema: ISO8601 | MODEL | TOOL | KIND | EXCERPT
log_line() {
  local seconds_ago="$1"
  local model="$2"
  local ts
  ts=$(date -u -d "$seconds_ago seconds ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v "-${seconds_ago}S" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
  printf '%s|%s|Bash|cyber-safeguards|excerpt\n' "$ts" "$model" >> "$LOG"
}

reset_state() {
  rm -f "$LOG"
  unset CC_MODEL_SWAP_SUGGESTER_DISABLE
  unset CC_MODEL_SWAP_SUGGESTER_QUIET
  unset CC_MODEL_SWAP_SUGGESTER_THRESHOLD
  unset CC_MODEL_SWAP_SUGGESTER_WINDOW_MIN
  unset CC_MODEL_SWAP_SUGGESTER_TARGET
  unset ANTHROPIC_MODEL
}

echo "Testing model-swap-suggester.sh"
echo "================================"

# Test 1: DISABLE=1 → silent, exit 0
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_DISABLE=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences entirely" pass
else
  run_test "DISABLE=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 2: QUIET=1 → silent, exit 0 even with blocks above threshold
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_QUIET=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences even with blocks above threshold" pass
else
  run_test "QUIET=1 (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: ANTHROPIC_MODEL unset → silent (default routing)
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "ANTHROPIC_MODEL unset → silent" pass
else
  run_test "Model unset (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 4: Sonnet pin → silent (unaffected)
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-sonnet-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Sonnet pin → silent" pass
else
  run_test "Sonnet pin (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 5: Haiku pin → silent (unaffected)
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-haiku-4-5 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Haiku pin → silent" pass
else
  run_test "Haiku pin (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 6: Opus pin, log missing → silent
reset_state
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Log missing → silent" pass
else
  run_test "Log missing (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 7: Opus pin, log empty → silent
reset_state
: > "$LOG"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Log empty → silent" pass
else
  run_test "Log empty (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 8: Opus pin, only Sonnet blocks logged → silent (no Opus evidence)
reset_state
log_line 60 "claude-sonnet-4-7"
log_line 120 "claude-sonnet-4-7"
log_line 180 "claude-sonnet-4-7"
log_line 240 "claude-sonnet-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Only Sonnet blocks in log → silent (Opus evidence missing)" pass
else
  run_test "Sonnet-only blocks (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 9: Opus pin, 1 block in window → silent (below default threshold 3)
reset_state
log_line 60 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "1 block (below threshold 3) → silent" pass
else
  run_test "1 block silent (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 10: Opus pin, 3 blocks in window → emit advisory
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "model-swap-suggester"; then
  run_test "3 blocks (at threshold) → advisory emitted" pass
else
  run_test "3 blocks advisory (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 11: Opus pin, 5 blocks in window → emit advisory with correct count
reset_state
for s in 30 60 90 120 180; do log_line "$s" "claude-opus-4-7"; done
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "5 Usage Policy block"; then
  run_test "5 blocks → advisory reports correct count" pass
else
  run_test "5 blocks count (OUT: $OUT)" fail
fi

# Test 12: Opus pin, all blocks outside window (older than WINDOW_MIN) → silent
reset_state
# WINDOW_MIN default 60. Place blocks 2 hours, 3 hours, 4 hours ago.
log_line 7200 "claude-opus-4-7"
log_line 10800 "claude-opus-4-7"
log_line 14400 "claude-opus-4-7"
log_line 18000 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Blocks outside window → silent" pass
else
  run_test "Stale blocks (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 13: Custom THRESHOLD=1, 1 block → emit
reset_state
log_line 60 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_THRESHOLD=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "1 Usage Policy block"; then
  run_test "Custom THRESHOLD=1 → 1 block triggers advisory" pass
else
  run_test "Custom threshold (OUT: $OUT)" fail
fi

# Test 14: Custom WINDOW_MIN=5, block at 4min ago → counted; block at 10min ago → not counted
reset_state
log_line 240 "claude-opus-4-7"   # 4 min ago → in window
log_line 600 "claude-opus-4-7"   # 10 min ago → outside window
log_line 720 "claude-opus-4-7"   # 12 min ago → outside window
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_WINDOW_MIN=5 CC_MODEL_SWAP_SUGGESTER_THRESHOLD=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "1 Usage Policy block"; then
  run_test "Custom WINDOW_MIN=5 → only in-window blocks counted" pass
else
  run_test "Custom window (OUT: $OUT)" fail
fi

# Test 15: Custom TARGET model appears verbatim in swap command
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_TARGET=claude-sonnet-4-6 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "ANTHROPIC_MODEL=claude-sonnet-4-6"; then
  run_test "Custom TARGET appears in swap command" pass
else
  run_test "Custom target (OUT: $OUT)" fail
fi

# Test 16: Default advisory contains concrete export command
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "export ANTHROPIC_MODEL=claude-sonnet-4-7"; then
  run_test "Default advisory includes concrete export command" pass
else
  run_test "Default export command (OUT: $OUT)" fail
fi

# Test 17: Advisory references both partner hooks
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "aup-false-positive-helper" && echo "$OUT" | grep -q "aup-block-pattern-logger"; then
  run_test "Advisory references both partner hooks" pass
else
  run_test "Partner hook references (OUT: $OUT)" fail
fi

# Test 18: Mixed Opus variants in log all count toward threshold
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-6"
log_line 180 "claude-opus-4-7[1m]"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "3 Usage Policy block"; then
  run_test "Mixed Opus variants all count (4-7 + 4-6 + 1m = 3)" pass
else
  run_test "Mixed Opus variants (OUT: $OUT)" fail
fi

# Test 19: Mixed Opus and Sonnet in log — only Opus counts
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-sonnet-4-7"
log_line 180 "claude-opus-4-7"
log_line 240 "claude-sonnet-4-7"
log_line 300 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "3 Usage Policy block"; then
  run_test "Sonnet blocks not counted (3 Opus + 2 Sonnet → 3)" pass
else
  run_test "Mixed Opus+Sonnet (OUT: $OUT)" fail
fi

# Test 20: Garbage env vars fall back to defaults (THRESHOLD=abc, WINDOW_MIN=xyz)
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_THRESHOLD=abc CC_MODEL_SWAP_SUGGESTER_WINDOW_MIN=xyz ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "3 Usage Policy block"; then
  run_test "Garbage env vars fall back to defaults" pass
else
  run_test "Garbage env vars (OUT: $OUT)" fail
fi

# Test 21: Unparseable timestamps are skipped (do not crash, do not count)
reset_state
printf 'BAD-TIMESTAMP|claude-opus-4-7|Bash|cyber-safeguards|excerpt\n' >> "$LOG"
printf 'also-bad|claude-opus-4-7|Bash|cyber-safeguards|excerpt\n' >> "$LOG"
log_line 60 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" CC_MODEL_SWAP_SUGGESTER_THRESHOLD=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
# Only the well-formed line should count.
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "1 Usage Policy block"; then
  run_test "Unparseable timestamps skipped without crash" pass
else
  run_test "Unparseable timestamps (exit=$EXIT, OUT: $OUT)" fail
fi

# Test 22: Hook never blocks the session (all paths exit 0)
reset_state
EXIT_CODES=""
for case in "disable" "quiet" "no-model" "sonnet" "no-log" "empty-log" "below-thresh" "above-thresh"; do
  reset_state
  case "$case" in
    "disable") OUT=$(CC_MODEL_SWAP_SUGGESTER_DISABLE=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "quiet") OUT=$(CC_MODEL_SWAP_SUGGESTER_QUIET=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "no-model") OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1); EXIT=$? ;;
    "sonnet") OUT=$(ANTHROPIC_MODEL=claude-sonnet-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "no-log") OUT=$(CC_AUP_BLOCK_LOG_PATH="$TMPDIR/nonexistent.log" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "empty-log") : > "$LOG"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "below-thresh") log_line 60 "claude-opus-4-7"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
    "above-thresh") log_line 60 "claude-opus-4-7"; log_line 120 "claude-opus-4-7"; log_line 180 "claude-opus-4-7"; OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks the session (8 paths all exit 0)" pass
else
  run_test "Exit codes (got: $EXIT_CODES)" fail
fi

# Test 23: GitHub tracker links present in advisory
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "github.com/anthropics/claude-code/issues/"; then
  run_test "Advisory includes GitHub tracker URLs" pass
else
  run_test "GitHub tracker URLs (OUT: $OUT)" fail
fi

# Test 24: Advisory shows current pinned model
reset_state
log_line 60 "claude-opus-4-6"
log_line 120 "claude-opus-4-6"
log_line 180 "claude-opus-4-6"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-6 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "Current model: claude-opus-4-6"; then
  run_test "Advisory shows current pinned model" pass
else
  run_test "Current model display (OUT: $OUT)" fail
fi

# Test 25: Default route through opt-in QUIET re-export instructions
reset_state
log_line 60 "claude-opus-4-7"
log_line 120 "claude-opus-4-7"
log_line 180 "claude-opus-4-7"
OUT=$(CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "export CC_MODEL_SWAP_SUGGESTER_QUIET=1"; then
  run_test "Advisory documents QUIET escape hatch" pass
else
  run_test "QUIET escape hatch (OUT: $OUT)" fail
fi

echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
