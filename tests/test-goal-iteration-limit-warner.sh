#!/bin/bash
# Tests for goal-iteration-limit-warner.sh

HOOK="$(dirname "$0")/../examples/goal-iteration-limit-warner.sh"
PASS=0 FAIL=0

TMPROOT="$(mktemp -d -t cc-goal-warn-test.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

run_test() {
  local desc="$1" expected_exit="$2" prompt="$3" extra_env="$4"
  local logfile="$TMPROOT/log-$RANDOM"
  local actual_exit
  local payload
  payload=$(jq -nc --arg p "$prompt" '{prompt:$p}')
  if [ -n "$extra_env" ]; then
    actual_exit=$(printf '%s' "$payload" | env CC_GOAL_WARN_LOG="$logfile" $extra_env bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
  else
    actual_exit=$(printf '%s' "$payload" | env CC_GOAL_WARN_LOG="$logfile" bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
  fi
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing goal-iteration-limit-warner.sh"
echo "======================================"

# 1. Empty prompt → pass
PAYLOAD='{"prompt":""}'
EXIT=$(printf '%s' "$PAYLOAD" | bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
[ "$EXIT" -eq 0 ] && { echo "  PASS: empty prompt passes"; PASS=$((PASS+1)); } || { echo "  FAIL: empty prompt"; FAIL=$((FAIL+1)); }

# 2. Non-/goal prompt → pass
run_test "regular prompt passes" 0 "please write a poem about cats"

# 3. /goal with no termination clause → warn (exit 0)
run_test "/goal without limit warns (default)" 0 "/goal find the death certificate for John Smith"

# 4. /goal with no termination clause in block mode → exit 2
run_test "/goal without limit blocks when action=block" 2 "/goal find the death certificate for John Smith" "CC_GOAL_WARN_ACTION=block"

# 5. /goal clear → pass silently
run_test "/goal clear passes silently" 0 "/goal clear"

# 6. /goal status → pass silently
run_test "/goal status passes silently" 0 "/goal status"

# 7. /goal evaluate-once → pass silently
run_test "/goal evaluate-once passes silently" 0 "/goal evaluate-once"

# 8. /goal with 'or stop after 20 turns' → pass
run_test "/goal with 'or stop after N turns' passes" 0 "/goal find the death certificate or stop after 20 turns"

# 9. /goal with 'max 15 iterations' → pass
run_test "/goal with 'max N iterations' passes" 0 "/goal find the source, max 15 iterations"

# 10. /goal with 'within 10 turns' → pass
run_test "/goal with 'within N turns' passes" 0 "/goal find it within 10 turns"

# 11. /goal with 'after 5 attempts' → pass
run_test "/goal with 'after N attempts' passes" 0 "/goal find it, give up after 5 attempts"

# 12. Bare /goal (just the command) → pass (informational)
run_test "/goal alone passes (informational)" 0 "/goal"

# 13. /goal help → pass
run_test "/goal help passes silently" 0 "/goal help"

# 14. /goal with embedded newlines → still detected
PAYLOAD=$(jq -nc '{prompt:"some context\n/goal find rare manuscript\nmore context"}')
EXIT=$(printf '%s' "$PAYLOAD" | bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
[ "$EXIT" -eq 0 ] && { echo "  PASS: /goal on a line within multi-line prompt detected"; PASS=$((PASS+1)); } || { echo "  FAIL: multi-line /goal"; FAIL=$((FAIL+1)); }

# 15. Disabled via env var → pass silently
run_test "CC_GOAL_WARN_DISABLE=1 disables hook" 0 "/goal find anything" "CC_GOAL_WARN_DISABLE=1"

# 16. Warning to stderr, stdout empty
PAYLOAD=$(jq -nc '{prompt:"/goal find a rare book"}')
STDOUT=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
STDERR=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$STDOUT" ] && echo "$STDERR" | grep -q "without a termination clause"; then
  echo "  PASS: stdout empty, stderr has warning"
  PASS=$((PASS+1))
else
  echo "  FAIL: stdout/stderr separation"
  FAIL=$((FAIL+1))
fi

# 17. Log file is created
LOG="$TMPROOT/goal.log"
PAYLOAD=$(jq -nc '{prompt:"/goal find something obscure"}')
printf '%s' "$PAYLOAD" | env CC_GOAL_WARN_LOG="$LOG" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$LOG" ] && grep -q "goal_without_limit" "$LOG"; then
  echo "  PASS: log file written"
  PASS=$((PASS+1))
else
  echo "  FAIL: log file missing"
  FAIL=$((FAIL+1))
fi

# 18. CC_GOAL_WARN_MAX_TURNS reflected in message
PAYLOAD=$(jq -nc '{prompt:"/goal find something"}')
STDERR=$(printf '%s' "$PAYLOAD" | env CC_GOAL_WARN_MAX_TURNS=42 bash "$HOOK" 2>&1 >/dev/null)
if echo "$STDERR" | grep -q "stop after 42 turns"; then
  echo "  PASS: custom max turns reflected in suggestion"
  PASS=$((PASS+1))
else
  echo "  FAIL: max turns env not reflected"
  FAIL=$((FAIL+1))
fi

# 19. /goal with uppercase 'STOP AFTER' → still recognized (case-insensitive)
run_test "/goal with 'STOP AFTER' (uppercase) passes" 0 "/goal find it OR STOP AFTER 10 TURNS"

# 20. /goal with extra spacing → still detected
run_test "/goal with multiple spaces detected" 0 "/goal     find rare information"

# 21. Prompt without /goal anywhere → pass
run_test "prompt containing 'goal' as a word passes" 0 "my goal here is to write good code"

echo "======================================"
echo "Result: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
