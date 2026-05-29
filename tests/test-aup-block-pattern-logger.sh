#!/bin/bash
# Tests for aup-block-pattern-logger.sh
HOOK="$(dirname "$0")/../examples/aup-block-pattern-logger.sh"
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

# Per-test scratch log; cleaned between cases.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
LOG="$TMPDIR/aup-block.log"

reset_log() {
  rm -f "$LOG"
  unset CC_AUP_BLOCK_LOGGER_DISABLE
  unset CC_AUP_BLOCK_LOGGER_QUIET
  unset CC_AUP_BLOCK_LOGGER_MAX_LINES
}

echo "Testing aup-block-pattern-logger.sh"
echo "===================================="

# Test 1: DISABLE=1 silences entirely, no log file created
reset_log
INPUT='{"tool_name":"Bash","tool_output":"API Error: ...violate our Usage Policy. This request triggered cyber-related safeguards."}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOGGER_DISABLE=1 CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ] && [ ! -f "$LOG" ]; then
  run_test "DISABLE=1 silences entirely, no log written" pass
else
  run_test "DISABLE=1 silences (exit=$EXIT, out_len=${#OUT}, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi

# Test 2: Empty input → silent exit
reset_log
OUT=$(printf '' | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ] && [ ! -f "$LOG" ]; then
  run_test "Empty stdin → silent, no log" pass
else
  run_test "Empty stdin (exit=$EXIT, out_len=${#OUT})" fail
fi

# Test 3: Tool output without AUP pattern → no log, no warning
reset_log
INPUT='{"tool_name":"Bash","tool_output":"normal output, no errors here"}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ] && [ ! -f "$LOG" ]; then
  run_test "Benign tool output → no log, no warning" pass
else
  run_test "Benign output (exit=$EXIT, out_len=${#OUT}, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi

# Test 4: cyber-safeguards pattern → log line + advisory
reset_log
INPUT='{"tool_name":"Bash","tool_output":"API Error: ...violate our Usage Policy. This request triggered cyber-related safeguards."}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
EXIT=$?
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [ "$EXIT" = "0" ] && [ "$LINE_COUNT" = "1" ] && grep -q "cyber-safeguards" "$LOG" && echo "$OUT" | grep -q "block detected"; then
  run_test "cyber-safeguards pattern → log + stderr advisory" pass
else
  run_test "cyber-safeguards pattern (exit=$EXIT, lines=$LINE_COUNT)" fail
fi

# Test 5: safety-guardrails pattern → log with correct kind
reset_log
INPUT='{"tool_name":"Edit","tool_output":"This request triggered safety guardrails. Rephrase your prompt or rewind to continue."}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" 2>&1)
if grep -q "safety-guardrails" "$LOG"; then
  run_test "safety-guardrails pattern recorded" pass
else
  run_test "safety-guardrails pattern (log: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 6: rephrase-rewind variant (cyber clause absent) → rephrase-rewind kind
reset_log
INPUT='{"tool_name":"Read","tool_output":"Rephrase your prompt or rewind to continue with this session."}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if grep -q "rephrase-rewind" "$LOG"; then
  run_test "rephrase-rewind pattern recorded" pass
else
  run_test "rephrase-rewind pattern (log: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 7: Generic API error fallback
reset_log
INPUT='{"tool_name":"Bash","tool_output":"API Error: Claude Code is unable to respond to this request right now."}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if grep -q "usage-policy-api" "$LOG"; then
  run_test "usage-policy-api fallback recorded" pass
else
  run_test "usage-policy-api fallback (log: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 8: QUIET=1 suppresses stderr but still logs
reset_log
INPUT='{"tool_name":"Bash","tool_output":"This request triggered cyber-related safeguards."}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" 2>&1)
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [ -z "$OUT" ] && [ "$LINE_COUNT" = "1" ]; then
  run_test "QUIET=1 suppresses stderr but still logs" pass
else
  run_test "QUIET=1 (out_len=${#OUT}, lines=$LINE_COUNT)" fail
fi

# Test 9: Log line schema — 5 pipe-delimited fields
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" >/dev/null 2>&1
FIELDS=$(awk -F'|' '{print NF}' "$LOG" 2>/dev/null)
if [ "$FIELDS" = "5" ]; then
  run_test "Log line has 5 pipe-delimited fields" pass
else
  run_test "Log schema fields=$FIELDS (line: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 10: Model field defaults to "default-routing" when ANTHROPIC_MODEL unset
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
unset ANTHROPIC_MODEL
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if awk -F'|' '{print $2}' "$LOG" | grep -q "default-routing"; then
  run_test "Model field is 'default-routing' when ANTHROPIC_MODEL unset" pass
else
  run_test "Model field default (line: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 11: Model field reflects ANTHROPIC_MODEL when set
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" >/dev/null 2>&1
if awk -F'|' '{print $2}' "$LOG" | grep -q "claude-opus-4-7"; then
  run_test "Model field reflects ANTHROPIC_MODEL pin" pass
else
  run_test "Model field pin (line: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 12: Cumulative count rises across invocations
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
for _ in 1 2 3; do
  printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" >/dev/null 2>&1
done
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [ "$LINE_COUNT" = "3" ]; then
  run_test "Three invocations → three log lines (idempotent append)" pass
else
  run_test "Cumulative log lines=$LINE_COUNT (expected 3)" fail
fi

# Test 13: Stderr advisory shows running count for the current model
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
# Seed 4 prior entries silently
for _ in 1 2 3 4; do
  printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" >/dev/null 2>&1
done
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" ANTHROPIC_MODEL=claude-opus-4-7 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -qE "Cumulative blocks logged for this model: 5"; then
  run_test "Advisory shows running count for current model" pass
else
  run_test "Running count advisory (OUT: $OUT)" fail
fi

# Test 14: Log rotation when CC_AUP_BLOCK_LOGGER_MAX_LINES exceeded
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
for _ in $(seq 1 12); do
  printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 CC_AUP_BLOCK_LOGGER_MAX_LINES=10 bash "$HOOK" >/dev/null 2>&1
done
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
# After 12 invocations with rotation threshold 10, log should be rotated down (keep half = 5)
# So the count should be at most 10, but rotation triggers when > 10 so we expect <= 6 (5 rotated + 1 new) on the next round
# We allow any value in [5, 10] since rotation timing depends on the order of append-then-check.
if [ "$LINE_COUNT" -ge 5 ] 2>/dev/null && [ "$LINE_COUNT" -le 10 ] 2>/dev/null; then
  run_test "Log rotation honors MAX_LINES (final lines=$LINE_COUNT, in [5,10])" pass
else
  run_test "Log rotation (final lines=$LINE_COUNT, expected 5-10)" fail
fi

# Test 15: Tool name extracted into log
reset_log
INPUT='{"tool_name":"Edit","tool_output":"triggered cyber-related safeguards"}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if awk -F'|' '{print $3}' "$LOG" | grep -q "^Edit$"; then
  run_test "Tool name field extracted correctly" pass
else
  run_test "Tool name extraction (line: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 16: Excerpt truncated to 120 chars max
reset_log
LONG=$(printf 'triggered cyber-related safeguards %.0s' $(seq 1 20))
INPUT="{\"tool_name\":\"Bash\",\"tool_output\":\"$LONG\"}"
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
EXCERPT=$(awk -F'|' '{print $5}' "$LOG")
EXCERPT_LEN=${#EXCERPT}
if [ "$EXCERPT_LEN" -le 120 ] 2>/dev/null; then
  run_test "Excerpt truncated to <=120 chars (got=$EXCERPT_LEN)" pass
else
  run_test "Excerpt length (got=$EXCERPT_LEN)" fail
fi

# Test 17: Pipe characters in output stripped from excerpt (schema safety)
reset_log
INPUT='{"tool_name":"Bash","tool_output":"line with | pipe | in it triggered cyber-related safeguards"}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
FIELDS=$(awk -F'|' '{print NF}' "$LOG")
if [ "$FIELDS" = "5" ]; then
  run_test "Pipes stripped from excerpt → schema preserved (5 fields)" pass
else
  run_test "Schema preserved with pipes in output (fields=$FIELDS)" fail
fi

# Test 18: Hook never blocks the tool (exit 0 in all paths)
reset_log
EXIT_CODES=""
for case in "disable" "empty" "benign" "block" "block+quiet"; do
  case "$case" in
    "disable") OUT=$(echo '{}' | CC_AUP_BLOCK_LOGGER_DISABLE=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "empty") OUT=$(printf '' | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1); EXIT=$? ;;
    "benign") OUT=$(echo '{"tool_name":"Bash","tool_output":"ok"}' | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1); EXIT=$? ;;
    "block") OUT=$(echo '{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}' | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1); EXIT=$? ;;
    "block+quiet") OUT=$(echo '{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}' | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" 2>&1); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks (all 5 paths exit 0)" pass
else
  run_test "Hook never blocks (exit codes: $EXIT_CODES)" fail
fi

# Test 19: Advisory mentions partner hook aup-false-positive-helper
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "aup-false-positive-helper"; then
  run_test "Advisory references partner hook" pass
else
  run_test "Partner hook reference (OUT: $OUT)" fail
fi

# Test 20: Advisory recommends Sonnet swap path
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
OUT=$(printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -qi "sonnet"; then
  run_test "Advisory recommends Sonnet swap" pass
else
  run_test "Advisory Sonnet swap (OUT: $OUT)" fail
fi

# Test 21: Pattern priority — cyber-safeguards wins over usage-policy when both present
reset_log
INPUT='{"tool_name":"Bash","tool_output":"violate our Usage Policy. This request triggered cyber-related safeguards."}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
KIND=$(awk -F'|' '{print $4}' "$LOG")
if [ "$KIND" = "cyber-safeguards" ]; then
  run_test "Pattern priority: cyber-safeguards beats usage-policy" pass
else
  run_test "Pattern priority (got kind=$KIND)" fail
fi

# Test 22: Custom CC_AUP_BLOCK_LOG_PATH honored
reset_log
CUSTOM_LOG="$TMPDIR/custom-aup.log"
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
printf '%s' "$INPUT" | CC_AUP_BLOCK_LOG_PATH="$CUSTOM_LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if [ -f "$CUSTOM_LOG" ] && grep -q "cyber-safeguards" "$CUSTOM_LOG"; then
  run_test "Custom log path honored" pass
else
  run_test "Custom log path (exists=$([ -f "$CUSTOM_LOG" ] && echo yes || echo no))" fail
fi

# Test 23: Missing jq fallback (simulate by setting PATH without jq)
reset_log
INPUT='{"tool_name":"Bash","tool_output":"triggered cyber-related safeguards"}'
# Create a temp PATH that omits jq. Resolve real on-disk binaries via /usr/bin and
# /bin so shell functions/aliases don't shadow the lookup.
NOJQ_DIR=$(mktemp -d)
for bin in bash cat head tail grep awk sed mkdir wc tr date printf rm mv ls dirname; do
  for candidate in /usr/bin/$bin /bin/$bin /usr/local/bin/$bin; do
    if [ -x "$candidate" ]; then
      ln -sf "$candidate" "$NOJQ_DIR/$bin"
      break
    fi
  done
done
OUT=$(printf '%s' "$INPUT" | PATH="$NOJQ_DIR" CC_AUP_BLOCK_LOG_PATH="$LOG" CC_AUP_BLOCK_LOGGER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
rm -rf "$NOJQ_DIR"
if [ "$EXIT" = "0" ] && [ -f "$LOG" ] && grep -q "cyber-safeguards" "$LOG"; then
  run_test "jq-missing fallback path → still logs (grep fallback)" pass
else
  run_test "jq fallback (exit=$EXIT, log exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi

echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
