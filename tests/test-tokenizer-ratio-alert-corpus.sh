#!/bin/bash
# Tests for tokenizer-ratio-alert-corpus.sh
HOOK="examples/tokenizer-ratio-alert-corpus.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

HISTORY="/tmp/cc-tokenizer-ratio-history"
SESSION_FLAG="/tmp/cc-tokenizer-ratio-session"
rm -f "$HISTORY" "$SESSION_FLAG"

# Test 1: Empty input exits cleanly with no log
OUT=$(echo "{}" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty input exit 0" "$RC" 0
if [ ! -f "$HISTORY" ] || [ ! -s "$HISTORY" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: history not empty for empty input"; fi

# Test 2: Missing tool_response exits cleanly without alert
INPUT='{"tool_input":{"command":"echo test"}}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "missing tokens exit 0" "$RC" 0
assert_not_contains "no alert without tokens" "$OUT" "tokenizer-ratio-alert-corpus"

# Test 3: Valid input logs entry
rm -f "$HISTORY" "$SESSION_FLAG"
INPUT='{"tool_input":{"command":"echo hello"},"tool_response":{"usage":{"input_tokens":100}}}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>&1)
RC=$?
assert_exit "valid input exit 0" "$RC" 0
if [ -f "$HISTORY" ] && [ -s "$HISTORY" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: history not written"; fi

# Test 4: Log entry format (timestamp|date|tokens|chars|ratio)
LINE=$(tail -1 "$HISTORY")
FIELDS=$(echo "$LINE" | awk -F'|' '{print NF}')
if [ "$FIELDS" -eq 5 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: log format wrong ($FIELDS fields, expected 5)"; fi

# Test 5: Below baseline threshold = no alert (under 50 turns = baseline not yet established)
rm -f "$HISTORY" "$SESSION_FLAG"
for i in $(seq 1 49); do
  echo '{"tool_input":{"command":"x"},"tool_response":{"usage":{"input_tokens":10}}}' | bash "$HOOK" 2>/dev/null
done
OUT=$(echo '{"tool_input":{"command":"y"},"tool_response":{"usage":{"input_tokens":10}}}' | bash "$HOOK" 2>&1)
assert_not_contains "no alert below baseline turn count" "$OUT" "tokenizer-ratio-alert-corpus"

# Test 6: After baseline + sustained 1.25x ratio, alert fires after 3 sessions
rm -f "$HISTORY" "$SESSION_FLAG"
# Establish baseline: 60 turns at ratio = 0.5 (tokens 50, chars 100)
for i in $(seq 1 60); do
  # Long string to give chars=~140
  echo '{"tool_input":{"command":"abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcde"},"tool_response":{"usage":{"input_tokens":50}}}' | bash "$HOOK" 2>/dev/null
done
# Now spike with ratio = 1.0 (tokens 140, chars ~140) — well over 1.25 × 0.36 baseline = 0.45 threshold
SPIKE_INPUT='{"tool_input":{"command":"abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcde"},"tool_response":{"usage":{"input_tokens":140}}}'
# Session 1 (export so subshell inherits)
export CLAUDE_SESSION_ID=session-1; OUT1=$(echo "$SPIKE_INPUT" | bash "$HOOK" 2>&1)
# Session 2
export CLAUDE_SESSION_ID=session-2; OUT2=$(echo "$SPIKE_INPUT" | bash "$HOOK" 2>&1)
# Session 3 — should trigger alert
export CLAUDE_SESSION_ID=session-3; OUT3=$(echo "$SPIKE_INPUT" | bash "$HOOK" 2>&1)
unset CLAUDE_SESSION_ID
assert_contains "session 3 alert fires" "$OUT3" "tokenizer-ratio-alert-corpus"
assert_contains "alert mentions baseline" "$OUT3" "baseline"
assert_contains "alert mentions Issue 46829" "$OUT3" "46829"

# Test 7: Hook is non-blocking (exit 0 even when alerting)
RC=$?
assert_exit "alert is non-blocking" "$RC" 0

# Cleanup
rm -f "$HISTORY" "$SESSION_FLAG"

echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
