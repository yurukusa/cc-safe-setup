#!/bin/bash
# Tests for pre-execution-claim-detector.sh
HOOK="$(dirname "$0")/../examples/pre-execution-claim-detector.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-pre-claim-test.XXXXXX"
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

# Helper: create a transcript with the given assistant text
make_transcript() {
  local file="$1"
  local text="$2"
  local model="${3:-claude-opus-4-8}"
  # Escape the text for JSON embedding
  printf '{"type":"user","message":{"content":"hi"}}\n' > "$file"
  jq -cn --arg t "$text" --arg m "$model" \
    '{type:"assistant",message:{model:$m,content:[{type:"text",text:$t}]}}' >> "$file"
}

echo "Testing pre-execution-claim-detector.sh"
echo "======================================="

# Test 1: opt-in env unset → silent exit, no log
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "the result was: \$891"
echo "{\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "opt-in env unset → silent, no log" pass
else
  run_test "opt-in env unset → silent, no log" fail
fi
rm -rf "$TEST_DIR"

# Test 2: opt-in but DISABLE=1 → silent
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "the result was: \$891"
echo "{\"session_id\":\"s2\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" \
  CC_OPUS48_PRE_CLAIM_DETECT=1 \
  CC_OPUS48_PRE_CLAIM_DISABLE=1 \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "DETECT=1 + DISABLE=1 → silent (disable wins)" pass
else
  run_test "DETECT=1 + DISABLE=1 → silent (disable wins)" fail
fi
rm -rf "$TEST_DIR"

# Test 3: missing transcript → silent exit
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/log.jsonl"
echo '{"session_id":"s3","tool_name":"Bash","transcript_path":"/nonexistent/file.jsonl"}' | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "missing transcript → silent exit" pass
else
  run_test "missing transcript → silent exit" fail
fi
rm -rf "$TEST_DIR"

# Test 4: Pattern 1 (claim-prefix) matches "the result was:"
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
make_transcript "$TRANSCRIPT" "the result was: foo bar"
echo "{\"session_id\":\"s4\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>"$STDERR_FILE"
if [ -f "$LOG" ] && grep -q '"pattern":"claim-prefix"' "$LOG" && \
   grep -q "Cluster 22" "$STDERR_FILE"; then
  run_test "Pattern 1: 'the result was:' → claim-prefix match" pass
else
  run_test "Pattern 1: 'the result was:' → claim-prefix match" fail
fi
rm -rf "$TEST_DIR"

# Test 5: Pattern 1 case-insensitive match
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "The Output Shows: something"
echo "{\"session_id\":\"s5\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"pattern":"claim-prefix"' "$LOG"; then
  run_test "Pattern 1: case-insensitive 'The Output Shows:'" pass
else
  run_test "Pattern 1: case-insensitive 'The Output Shows:'" fail
fi
rm -rf "$TEST_DIR"

# Test 6: Pattern 2 (action-then-value): "I confirmed X and Y"
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "I confirmed the deployment and everything looks healthy"
echo "{\"session_id\":\"s6\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"pattern":"action-then-value"' "$LOG"; then
  run_test "Pattern 2: 'I confirmed X and Y' → action-then-value" pass
else
  run_test "Pattern 2: 'I confirmed X and Y' → action-then-value" fail
fi
rm -rf "$TEST_DIR"

# Test 7: Pattern 3 (bare price claim, no hedge)
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "The flight costs \$891 per person."
echo "{\"session_id\":\"s7\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"pattern":"bare-price-claim"' "$LOG"; then
  run_test "Pattern 3: bare price '\$891' without hedge → bare-price-claim" pass
else
  run_test "Pattern 3: bare price '\$891' without hedge → bare-price-claim" fail
fi
rm -rf "$TEST_DIR"

# Test 8: Pattern 3 suppressed when hedge precedes
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "Let me check the flight prices. I'll search for the \$891 fare to see if it's still available."
echo "{\"session_id\":\"s8\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "Pattern 3 hedge suppresses bare-price ('let me check' preceded \$891)" pass
else
  run_test "Pattern 3 hedge suppresses bare-price ('let me check' preceded \$891)" fail
fi
rm -rf "$TEST_DIR"

# Test 9: Pattern 4 (bare SHA-like 40 hex chars)
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "The latest commit is a1b2c3d4e5f6789012345678901234567890abcd on main."
echo "{\"session_id\":\"s9\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"pattern":"bare-sha-claim"' "$LOG"; then
  run_test "Pattern 4: bare SHA → bare-sha-claim" pass
else
  run_test "Pattern 4: bare SHA → bare-sha-claim" fail
fi
rm -rf "$TEST_DIR"

# Test 10: Pattern 4 suppressed when "let me run" precedes
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "Let me run git log. The SHA might be a1b2c3d4e5f6789012345678901234567890abcd if uncommitted."
echo "{\"session_id\":\"s10\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "Pattern 4 hedge suppresses bare-sha ('let me run' precedes)" pass
else
  run_test "Pattern 4 hedge suppresses bare-sha ('let me run' precedes)" fail
fi
rm -rf "$TEST_DIR"

# Test 11: Pattern 5 (file-path-then-block) — `path` followed by ``` block
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "The file \`/etc/config.yaml\` contains:
\`\`\`yaml
key: value
\`\`\`"
echo "{\"session_id\":\"s11\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ -f "$LOG" ] && grep -q '"pattern":"file-path-then-block"' "$LOG"; then
  run_test "Pattern 5: backtick file path + code block → file-path-then-block" pass
else
  run_test "Pattern 5: backtick file path + code block → file-path-then-block" fail
fi
rm -rf "$TEST_DIR"

# Test 12: benign assistant text → no match
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "I'll now run the analysis. Let me check the configuration first."
echo "{\"session_id\":\"s12\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "benign text → no match" pass
else
  run_test "benign text → no match" fail
fi
rm -rf "$TEST_DIR"

# Test 13: QUIET=1 suppresses entirely
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "the result was: foo"
echo "{\"session_id\":\"s13\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" \
  CC_OPUS48_PRE_CLAIM_DETECT=1 \
  CC_OPUS48_PRE_CLAIM_QUIET=1 \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "QUIET=1 → silent (no log)" pass
else
  run_test "QUIET=1 → silent (no log)" fail
fi
rm -rf "$TEST_DIR"

# Test 14: stderr advisory includes anchor issue #64065
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
make_transcript "$TRANSCRIPT" "the file contains: x"
echo "{\"session_id\":\"s14\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>"$STDERR_FILE"
if grep -q "#64065" "$STDERR_FILE"; then
  run_test "stderr includes anchor #64065" pass
else
  run_test "stderr includes anchor #64065" fail
fi
rm -rf "$TEST_DIR"

# Test 15: stderr advisory includes Opus 4.7 fallback
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
STDERR_FILE="$TEST_DIR/stderr"
make_transcript "$TRANSCRIPT" "the response was: y"
echo "{\"session_id\":\"s15\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>"$STDERR_FILE"
if grep -q "claude-opus-4-7" "$STDERR_FILE"; then
  run_test "stderr includes Opus 4.7 fallback path" pass
else
  run_test "stderr includes Opus 4.7 fallback path" fail
fi
rm -rf "$TEST_DIR"

# Test 16: log records model from transcript
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "the result was: q" "claude-opus-4-8"
echo "{\"session_id\":\"s16\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if grep -q '"model":"claude-opus-4-8"' "$LOG"; then
  run_test "log records model from transcript" pass
else
  run_test "log records model from transcript" fail
fi
rm -rf "$TEST_DIR"

# Test 17: log records tool_name from input
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "the result was: q"
echo "{\"session_id\":\"s17\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if grep -q '"tool":"Bash"' "$LOG"; then
  run_test "log records tool name from input" pass
else
  run_test "log records tool name from input" fail
fi
rm -rf "$TEST_DIR"

# Test 18: corrupted JSON input → exit 0 quietly
TEST_DIR=$(mktempd)
LOG="$TEST_DIR/log.jsonl"
echo 'not json {{{' | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "corrupted JSON → exit 0, no log" pass
else
  run_test "corrupted JSON → exit 0, no log (exit=$EXIT)" fail
fi
rm -rf "$TEST_DIR"

# Test 19: empty transcript → silent
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
touch "$TRANSCRIPT"
echo "{\"session_id\":\"s19\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
EXIT=$?
if [ "$EXIT" = "0" ] && [ ! -f "$LOG" ]; then
  run_test "empty transcript → silent" pass
else
  run_test "empty transcript → silent" fail
fi
rm -rf "$TEST_DIR"

# Test 20: only-user-message transcript → silent (no assistant text)
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
echo '{"type":"user","message":{"content":"the result was: \$891"}}' > "$TRANSCRIPT"
echo "{\"session_id\":\"s20\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if [ ! -f "$LOG" ]; then
  run_test "only-user-message → no match (skip user text)" pass
else
  run_test "only-user-message → no match (skip user text)" fail
fi
rm -rf "$TEST_DIR"

# Test 21: log includes ISO 8601 UTC timestamp
TEST_DIR=$(mktempd)
TRANSCRIPT="$TEST_DIR/t.jsonl"
LOG="$TEST_DIR/log.jsonl"
make_transcript "$TRANSCRIPT" "the file was: yes"
echo "{\"session_id\":\"s21\",\"tool_name\":\"Bash\",\"transcript_path\":\"$TRANSCRIPT\"}" | \
  CC_OPUS48_PRE_CLAIM_LOG="$LOG" CC_OPUS48_PRE_CLAIM_DETECT=1 \
  bash "$HOOK" 2>/dev/null
if grep -qE '"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$LOG"; then
  run_test "log includes ISO 8601 UTC timestamp" pass
else
  run_test "log includes ISO 8601 UTC timestamp" fail
fi
rm -rf "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
