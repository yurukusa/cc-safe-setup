#!/bin/bash
# Tests for opus-degradation-tracker.sh
HOOK="$(dirname "$0")/../examples/opus-degradation-tracker.sh"
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

mktmplog() {
  mktemp -t opus-degradation-tracker-test.XXXXXX
}

echo "Testing opus-degradation-tracker.sh"
echo "===================================="

# Test 1: QUIET=1 silences regardless of state
LOG=$(mktmplog)
echo "2026-04-01 10:00 task fail" > "$LOG"
OUT=$(CC_EVAL_LOG_PATH=$LOG CC_OPUS_DEGRADATION_TRACKER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences" pass
else
  run_test "QUIET=1 silences (exit=$EXIT, out_len=${#OUT})" fail
fi
rm -f "$LOG"

# Test 2: log file does not exist → silent
OUT=$(CC_EVAL_LOG_PATH=/tmp/nonexistent-cc-eval-log-$$ bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Missing log file → silent" pass
else
  run_test "Missing log → silent (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: log file exists but is empty → silent
LOG=$(mktmplog)
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Empty log → silent" pass
else
  run_test "Empty log → silent (exit=$EXIT, out_len=${#OUT})" fail
fi
rm -f "$LOG"

# Test 4: log with too few entries → silent (insufficient samples)
LOG=$(mktmplog)
for i in $(seq 1 10); do
  echo "2026-04-0$((i % 9 + 1)) 10:00 task pass" >> "$LOG"
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Below MIN_SAMPLES → silent" pass
else
  run_test "Below MIN_SAMPLES (exit=$EXIT, out_len=${#OUT})" fail
fi
rm -f "$LOG"

# Test 5: log with healthy recent pass rate → silent
LOG=$(mktmplog)
# 30 baseline entries 35-60 days ago, all pass (100%)
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso baseline-task pass" >> "$LOG"
done
# 10 recent entries 1-5 days ago, all pass (100%)
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso recent-task pass" >> "$LOG"
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Healthy pass rate → silent" pass
else
  run_test "Healthy → silent (exit=$EXIT, out_len=${#OUT})" fail
fi
rm -f "$LOG"

# Test 6: log with degraded pass rate → emit advisory
LOG=$(mktmplog)
# 26 baseline entries (35-60 days ago), 24 pass / 2 fail = 92.3%
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  if [ "$i" -le 36 ]; then
    echo "$date_iso baseline-task fail" >> "$LOG"
  else
    echo "$date_iso baseline-task pass" >> "$LOG"
  fi
done
# 10 recent entries (1-5 days ago), 2 pass / 8 fail = 20%
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  if [ "$i" -le 1 ]; then
    echo "$date_iso recent-task pass" >> "$LOG"
  else
    echo "$date_iso recent-task fail" >> "$LOG"
  fi
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "Personal pass rate dropped"; then
  run_test "Degraded pass rate → advisory emitted" pass
else
  run_test "Degraded → advisory (exit=$EXIT, out_len=${#OUT})" fail
fi
rm -f "$LOG"

# Test 7: Advisory references Margin Lab Gist
LOG=$(mktmplog)
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso baseline-task pass" >> "$LOG"
done
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso recent-task fail" >> "$LOG"
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "Margin Lab"; then
  run_test "Advisory references Margin Lab" pass
else
  run_test "Advisory references Margin Lab" fail
fi
rm -f "$LOG"

# Test 8: Advisory references Migration Playbook v2
LOG=$(mktmplog)
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso baseline-task pass" >> "$LOG"
done
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso recent-task fail" >> "$LOG"
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "claude-code-migration-playbook"; then
  run_test "Advisory references Migration Playbook v2" pass
else
  run_test "Advisory references Migration Playbook v2" fail
fi
rm -f "$LOG"

# Test 9: Advisory mentions QUIET env var as opt-out
LOG=$(mktmplog)
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso baseline-task pass" >> "$LOG"
done
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso recent-task fail" >> "$LOG"
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_OPUS_DEGRADATION_TRACKER_QUIET"; then
  run_test "Advisory mentions opt-out env var" pass
else
  run_test "Advisory mentions opt-out env var" fail
fi
rm -f "$LOG"

# Test 10: Malformed log lines are silently skipped
LOG=$(mktmplog)
echo "this is not a valid line" >> "$LOG"
echo "" >> "$LOG"
echo "garbage-data-here" >> "$LOG"
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso baseline-task pass" >> "$LOG"
done
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso recent-task fail" >> "$LOG"
done
OUT=$(CC_EVAL_LOG_PATH=$LOG bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "Personal pass rate dropped"; then
  run_test "Malformed lines silently skipped, valid entries still computed" pass
else
  run_test "Malformed lines skipped (exit=$?, out=${OUT:0:80})" fail
fi
rm -f "$LOG"

# Test 11: Custom threshold respected (delta below threshold → silent)
LOG=$(mktmplog)
# Baseline 26 pass (100%)
for i in $(seq 35 60); do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  echo "$date_iso baseline-task pass" >> "$LOG"
done
# Recent 9/10 pass = 90% (delta = 10pp)
for i in 1 1 2 2 3 3 4 4 5 5; do
  date_iso=$(date -d "$i days ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
  if [ -z "$date_iso" ]; then date_iso=$(date -v "-${i}d" '+%Y-%m-%d %H:%M' 2>/dev/null); fi
  if [ "$i" -le 1 ]; then
    echo "$date_iso recent-task fail" >> "$LOG"
  else
    echo "$date_iso recent-task pass" >> "$LOG"
  fi
done
# With threshold=20, 10pp < 20pp → silent
OUT=$(CC_EVAL_LOG_PATH=$LOG CC_OPUS_DEGRADATION_TRACKER_THRESHOLD=20 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "Threshold higher than observed delta → silent" pass
else
  run_test "Threshold=20 silent on delta=10 (exit=$EXIT, out_len=${#OUT})" fail
fi
rm -f "$LOG"

# Test 12: Helper functions documented in hook comments
if grep -q "cc-eval-pass" "$HOOK" && grep -q "cc-eval-fail" "$HOOK"; then
  run_test "Hook documents cc-eval-pass / cc-eval-fail helper functions" pass
else
  run_test "Hook documents helper functions" fail
fi

# Test 13: Hook documents CC_EVAL_LOG_PATH env var
if grep -q "CC_EVAL_LOG_PATH" "$HOOK"; then
  run_test "Hook documents CC_EVAL_LOG_PATH" pass
else
  run_test "Hook documents CC_EVAL_LOG_PATH" fail
fi

# Test 14: Hook documents CC_OPUS_DEGRADATION_TRACKER_BASELINE_DAYS
if grep -q "CC_OPUS_DEGRADATION_TRACKER_BASELINE_DAYS" "$HOOK"; then
  run_test "Hook documents BASELINE_DAYS env var" pass
else
  run_test "Hook documents BASELINE_DAYS env var" fail
fi

# Test 15: Hook documents settings.json snippet
if grep -q "SessionStart" "$HOOK" && grep -q "settings.json" "$HOOK"; then
  run_test "Hook documents settings.json config" pass
else
  run_test "Hook documents settings.json config" fail
fi

# Test 16: Background section references the May 22 signal
if grep -q "2026-05-22" "$HOOK"; then
  run_test "Hook background references 2026-05-22 degradation signal" pass
else
  run_test "Hook background references 2026-05-22" fail
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
