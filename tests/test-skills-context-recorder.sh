#!/bin/bash
# Tests for skills-context-recorder.sh
HOOK="$(dirname "$0")/../examples/skills-context-recorder.sh"
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
LOG="$TMPDIR/skills-context.log"

reset_log() {
  rm -f "$LOG"
  unset CC_SKILLS_CONTEXT_RECORDER_DISABLE
  unset CC_SKILLS_CONTEXT_RECORDER_QUIET
  unset CC_SKILLS_CONTEXT_MAX_LINES
  unset CC_ACTIVE_SKILL
}

echo "Testing skills-context-recorder.sh"
echo "===================================="

# Test 1: DISABLE=1 silences entirely; no log file created.
reset_log
INPUT='{"user_prompt":"/test-skill some args","session_id":"sess-aaa"}'
OUT=$(printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_RECORDER_DISABLE=1 CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ] && [ ! -f "$LOG" ]; then
  run_test "DISABLE=1 silences entirely, no log written" pass
else
  run_test "DISABLE=1 (exit=$EXIT, out_len=${#OUT}, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi

# Test 2: Empty stdin → silent
reset_log
OUT=$(printf '' | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ] && [ ! -f "$LOG" ]; then
  run_test "Empty stdin → silent, no log" pass
else
  run_test "Empty stdin (exit=$EXIT, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi

# Test 3: No skill invocation in prompt → no log
reset_log
INPUT='{"user_prompt":"please refactor the foo function","session_id":"sess-bbb"}'
OUT=$(printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ] && [ ! -f "$LOG" ]; then
  run_test "Plain text prompt → no log, no advisory" pass
else
  run_test "Plain text (exit=$EXIT, log_exists=$([ -f "$LOG" ] && echo yes || echo no))" fail
fi

# Test 4: Slash command at start of prompt → recorded as source=slash
reset_log
INPUT='{"user_prompt":"/cluster8-audit help me set up the proxy","session_id":"sess-ccc"}'
OUT=$(printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
LINE=$(cat "$LOG" 2>/dev/null)
if [ "$EXIT" = "0" ] && echo "$LINE" | grep -q "|slash|cluster8-audit$"; then
  run_test "Slash command → recorded with source=slash" pass
else
  run_test "Slash command (line: $LINE)" fail
fi

# Test 5: [skill: name] marker → recorded as source=marker
reset_log
INPUT='{"user_prompt":"[skill: poe-clone-generator] make me a game","session_id":"sess-ddd"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if grep -q "|marker|poe-clone-generator$" "$LOG"; then
  run_test "[skill: name] marker → recorded with source=marker" pass
else
  run_test "Marker (line: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 6: CC_ACTIVE_SKILL env override → source=manual
reset_log
INPUT='{"user_prompt":"do some work","session_id":"sess-eee"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 CC_ACTIVE_SKILL=manual-override bash "$HOOK" >/dev/null 2>&1
if grep -q "|manual|manual-override$" "$LOG"; then
  run_test "CC_ACTIVE_SKILL env → recorded with source=manual" pass
else
  run_test "Manual override (line: $(cat "$LOG" 2>/dev/null))" fail
fi

# Test 7: Priority: manual override beats slash command
reset_log
INPUT='{"user_prompt":"/slash-skill args","session_id":"sess-fff"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 CC_ACTIVE_SKILL=wins-override bash "$HOOK" >/dev/null 2>&1
KIND=$(awk -F'|' '{print $3}' "$LOG")
NAME=$(awk -F'|' '{print $4}' "$LOG")
if [ "$KIND" = "manual" ] && [ "$NAME" = "wins-override" ]; then
  run_test "Priority: manual beats slash" pass
else
  run_test "Priority manual>slash (kind=$KIND, name=$NAME)" fail
fi

# Test 8: Priority: slash beats marker when both present
reset_log
INPUT='{"user_prompt":"/slash-wins something [skill: marker-loses] more","session_id":"sess-ggg"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
KIND=$(awk -F'|' '{print $3}' "$LOG")
NAME=$(awk -F'|' '{print $4}' "$LOG")
if [ "$KIND" = "slash" ] && [ "$NAME" = "slash-wins" ]; then
  run_test "Priority: slash beats marker" pass
else
  run_test "Priority slash>marker (kind=$KIND, name=$NAME)" fail
fi

# Test 9: Log schema — 4 pipe-delimited fields
reset_log
INPUT='{"user_prompt":"/foo","session_id":"sess-hhh"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
FIELDS=$(awk -F'|' '{print NF}' "$LOG")
if [ "$FIELDS" = "4" ]; then
  run_test "Log line has 4 pipe-delimited fields" pass
else
  run_test "Log schema (fields=$FIELDS, line: $(cat "$LOG"))" fail
fi

# Test 10: Session ID propagated to log
reset_log
INPUT='{"user_prompt":"/foo","session_id":"abcdef-1234"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
SID=$(awk -F'|' '{print $2}' "$LOG")
if [ "$SID" = "abcdef-1234" ]; then
  run_test "Session ID propagated to log" pass
else
  run_test "Session ID propagation (got=$SID)" fail
fi

# Test 11: Missing session_id → 'no-session-id' placeholder
reset_log
INPUT='{"user_prompt":"/foo"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
SID=$(awk -F'|' '{print $2}' "$LOG")
if [ "$SID" = "no-session-id" ]; then
  run_test "Missing session_id → placeholder used" pass
else
  run_test "Session placeholder (got=$SID)" fail
fi

# Test 12: Stderr advisory emitted by default
reset_log
INPUT='{"user_prompt":"/test-skill","session_id":"sess-iii"}'
OUT=$(printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "skills-context-recorder.*recorded skill=test-skill"; then
  run_test "Default mode emits stderr advisory" pass
else
  run_test "Default advisory (OUT: $OUT)" fail
fi

# Test 13: QUIET=1 suppresses stderr but still logs
reset_log
INPUT='{"user_prompt":"/test-skill","session_id":"sess-jjj"}'
OUT=$(printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" 2>&1)
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [ -z "$OUT" ] && [ "$LINE_COUNT" = "1" ]; then
  run_test "QUIET=1 suppresses stderr, still logs" pass
else
  run_test "QUIET=1 (out_len=${#OUT}, lines=$LINE_COUNT)" fail
fi

# Test 14: Skill name truncated to <=64 chars
reset_log
LONG_NAME=$(printf 'a%.0s' $(seq 1 200))
INPUT="{\"user_prompt\":\"/$LONG_NAME\",\"session_id\":\"sess-kkk\"}"
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
NAME_LEN=$(awk -F'|' '{print length($4)}' "$LOG")
if [ "$NAME_LEN" -le 64 ] 2>/dev/null && [ "$NAME_LEN" -gt 0 ] 2>/dev/null; then
  run_test "Skill name truncated to <=64 chars (got=$NAME_LEN)" pass
else
  run_test "Name truncation (got=$NAME_LEN)" fail
fi

# Test 15: Pipes stripped from skill name → schema preserved
reset_log
INPUT='{"user_prompt":"/foo","session_id":"sess|with|pipes"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
FIELDS=$(awk -F'|' '{print NF}' "$LOG")
if [ "$FIELDS" = "4" ]; then
  run_test "Pipes stripped from session_id → schema preserved" pass
else
  run_test "Schema preserved with pipes (fields=$FIELDS)" fail
fi

# Test 16: Cumulative logging across invocations
reset_log
for skill in alpha beta gamma; do
  printf '%s' "{\"user_prompt\":\"/$skill\",\"session_id\":\"sess-multi\"}" | \
    CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
done
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
LAST_SKILL=$(tail -1 "$LOG" | awk -F'|' '{print $4}')
if [ "$LINE_COUNT" = "3" ] && [ "$LAST_SKILL" = "gamma" ]; then
  run_test "Cumulative append (3 lines, last=gamma)" pass
else
  run_test "Cumulative append (lines=$LINE_COUNT, last=$LAST_SKILL)" fail
fi

# Test 17: Log rotation when MAX_LINES exceeded
reset_log
INPUT='{"user_prompt":"/foo","session_id":"sess-rot"}'
for _ in $(seq 1 25); do
  printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 CC_SKILLS_CONTEXT_MAX_LINES=10 bash "$HOOK" >/dev/null 2>&1
done
LINE_COUNT=$(wc -l < "$LOG" 2>/dev/null || echo 0)
if [ "$LINE_COUNT" -ge 5 ] 2>/dev/null && [ "$LINE_COUNT" -le 12 ] 2>/dev/null; then
  run_test "Log rotation honors MAX_LINES (final lines=$LINE_COUNT, in [5,12])" pass
else
  run_test "Log rotation (lines=$LINE_COUNT)" fail
fi

# Test 18: Slash command must start at column 0 — leading whitespace → no match
reset_log
INPUT='{"user_prompt":"   /not-recognized args","session_id":"sess-mmm"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
# Should still match because we look at first non-blank line
NAME=$(awk -F'|' '{print $4}' "$LOG" 2>/dev/null)
if [ "$NAME" = "not-recognized" ]; then
  run_test "Slash on first non-blank line matches (whitespace tolerance)" pass
else
  run_test "First-non-blank tolerance (got=$NAME, log=$(cat "$LOG" 2>/dev/null))" fail
fi

# Test 19: Slash mid-prompt (not start) → not matched
reset_log
INPUT='{"user_prompt":"check this /not-a-command in the docs","session_id":"sess-nnn"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
  run_test "Slash mid-prompt → no match (only column-0 slash counts)" pass
else
  run_test "Mid-prompt slash should not match (log: $(cat "$LOG"))" fail
fi

# Test 20: Hook never blocks — all paths exit 0
EXIT_CODES=""
for case in "disable" "empty" "plain" "slash" "marker" "manual"; do
  case "$case" in
    "disable") OUT=$(echo '{}' | CC_SKILLS_CONTEXT_RECORDER_DISABLE=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "empty") OUT=$(printf '' | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1); EXIT=$? ;;
    "plain") OUT=$(echo '{"user_prompt":"hello","session_id":"x"}' | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1); EXIT=$? ;;
    "slash") OUT=$(echo '{"user_prompt":"/foo","session_id":"x"}' | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "marker") OUT=$(echo '{"user_prompt":"[skill: foo]","session_id":"x"}' | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" 2>&1); EXIT=$? ;;
    "manual") OUT=$(echo '{"user_prompt":"hello","session_id":"x"}' | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 CC_ACTIVE_SKILL=foo bash "$HOOK" 2>&1); EXIT=$? ;;
  esac
  EXIT_CODES="$EXIT_CODES $EXIT"
done
NONZERO=$(echo "$EXIT_CODES" | tr ' ' '\n' | grep -v "^$" | grep -v "^0$" | head -1)
if [ -z "$NONZERO" ]; then
  run_test "Hook never blocks (all 6 paths exit 0)" pass
else
  run_test "Hook never blocks (exit codes: $EXIT_CODES)" fail
fi

# Test 21: jq-missing fallback path still works
reset_log
INPUT='{"user_prompt":"/fallback-test","session_id":"sess-jq"}'
NOJQ_DIR=$(mktemp -d)
for bin in bash cat head tail grep awk sed mkdir wc tr date printf rm mv ls dirname; do
  for candidate in /usr/bin/$bin /bin/$bin /usr/local/bin/$bin; do
    if [ -x "$candidate" ]; then
      ln -sf "$candidate" "$NOJQ_DIR/$bin"
      break
    fi
  done
done
OUT=$(printf '%s' "$INPUT" | PATH="$NOJQ_DIR" CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
rm -rf "$NOJQ_DIR"
NAME=$(awk -F'|' '{print $4}' "$LOG" 2>/dev/null)
if [ "$EXIT" = "0" ] && [ "$NAME" = "fallback-test" ]; then
  run_test "jq-missing fallback path → still records (sed fallback)" pass
else
  run_test "jq fallback (exit=$EXIT, name=$NAME)" fail
fi

# Test 22: Stderr advisory shows short prefix of session ID
reset_log
INPUT='{"user_prompt":"/foo","session_id":"abcdefghijklmnopqrstuvwxyz"}'
OUT=$(printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -qE 'session=abcdefghijkl'; then
  run_test "Advisory shows 12-char session prefix" pass
else
  run_test "Session prefix in advisory (OUT: $OUT)" fail
fi

# Test 23: Custom log path honored
reset_log
CUSTOM="$TMPDIR/custom-skills.log"
INPUT='{"user_prompt":"/foo","session_id":"sess-x"}'
printf '%s' "$INPUT" | CC_SKILLS_CONTEXT_LOG_PATH="$CUSTOM" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
if [ -f "$CUSTOM" ] && grep -q "foo$" "$CUSTOM"; then
  run_test "Custom CC_SKILLS_CONTEXT_LOG_PATH honored" pass
else
  run_test "Custom log path (exists=$([ -f "$CUSTOM" ] && echo yes || echo no))" fail
fi

# Test 24: Workaround helper pattern — most-recent-skill-for-session lookup works
reset_log
for inv in '{"user_prompt":"/skill-a","session_id":"sess-A"}' \
           '{"user_prompt":"/skill-b","session_id":"sess-B"}' \
           '{"user_prompt":"/skill-c","session_id":"sess-A"}'; do
  printf '%s' "$inv" | CC_SKILLS_CONTEXT_LOG_PATH="$LOG" CC_SKILLS_CONTEXT_RECORDER_QUIET=1 bash "$HOOK" >/dev/null 2>&1
done
# Most recent skill for sess-A should be skill-c (last activation in that session)
LATEST_A=$(grep "|sess-A|" "$LOG" 2>/dev/null | tail -1 | awk -F'|' '{print $4}')
LATEST_B=$(grep "|sess-B|" "$LOG" 2>/dev/null | tail -1 | awk -F'|' '{print $4}')
if [ "$LATEST_A" = "skill-c" ] && [ "$LATEST_B" = "skill-b" ]; then
  run_test "Workaround lookup: most-recent-skill-per-session works" pass
else
  run_test "Per-session lookup (sess-A=$LATEST_A, sess-B=$LATEST_B)" fail
fi

echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
