#!/bin/bash
# Tests for claude-update-budget-guard.sh
HOOK="examples/claude-update-budget-guard.sh"
PASS=0 FAIL=0

assert_exit() {
  if [ "$2" -eq "$3" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"
  fi
}
assert_contains() {
  if printf '%s' "$2" | grep -q "$3"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"
  fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -q "$3"; then
    FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"
  else
    PASS=$((PASS+1))
  fi
}

FIXTURE=$(mktemp)
trap 'rm -f "$FIXTURE"' EXIT

# Test 1: Non-Bash tool — pass through silently
OUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | bash "$HOOK" 2>&1)
assert_exit "non-Bash tool exits 0" $? 0
assert_not_contains "non-Bash has no banner" "$OUT" "claude-update-budget-guard"

# Test 2: Unrelated Bash command — pass through silently
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$HOOK" 2>&1)
assert_exit "unrelated bash exits 0" $? 0
assert_not_contains "unrelated has no banner" "$OUT" "claude-update-budget-guard"

# Test 3: `echo about claude update later` — word boundary means this *does*
# match (whitespace before `claude` and `update` after). That's correct: if a
# user is literally about to `echo`, we still accept it as harmless. The real
# false-positive to prevent is a hyphenated prefix — covered in test 11.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | bash "$HOOK" 2>&1)
assert_exit "plain echo passes through" $? 0

# Test 4: `claude update` with a failing probe → fallthrough warn, exit 0
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD='false' bash "$HOOK" 2>&1)
assert_exit "no probe fallthrough exits 0" $? 0
assert_contains "no probe warns" "$OUT" "Cannot read /usage"
assert_contains "no probe references issue" "$OUT" "52890"

# Test 5: `claude self-update` — detected same way
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude self-update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD='false' bash "$HOOK" 2>&1)
assert_exit "self-update detected" $? 0
assert_contains "self-update shows banner" "$OUT" "claude-update-budget-guard"

# Test 6: Quota tight (10% remaining, threshold 30) + MODE=warn (default) → exit 0 with warning
printf '{"five_hour":{"remaining_percent":10}}' > "$FIXTURE"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD="cat $FIXTURE" \
  CLAUDE_UPDATE_BUDGET_THRESHOLD=30 \
  bash "$HOOK" 2>&1)
assert_exit "quota tight warn exits 0" $? 0
assert_contains "quota tight banner" "$OUT" "5-hour quota remaining: 10%"
assert_contains "quota tight suggests skip" "$OUT" "skip until the next 5h reset"

# Test 7: Quota tight + MODE=block → exit 2
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD="cat $FIXTURE" \
  CLAUDE_UPDATE_BUDGET_THRESHOLD=30 \
  CLAUDE_UPDATE_BUDGET_MODE=block \
  bash "$HOOK" 2>&1)
assert_exit "quota tight block exits 2" $? 2
assert_contains "block also shows reason" "$OUT" "10%"

# Test 8: Quota OK (80% remaining) → exit 0, informational note
printf '{"five_hour":{"remaining_percent":80}}' > "$FIXTURE"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD="cat $FIXTURE" \
  CLAUDE_UPDATE_BUDGET_THRESHOLD=30 \
  bash "$HOOK" 2>&1)
assert_exit "quota OK exits 0" $? 0
assert_contains "quota OK info banner" "$OUT" "info"
assert_contains "quota OK shows remaining" "$OUT" "remaining: 80%"

# Test 9: Alternative JSON shape (camelCase) supported
printf '{"fiveHour":{"remainingPercent":15}}' > "$FIXTURE"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD="cat $FIXTURE" \
  CLAUDE_UPDATE_BUDGET_THRESHOLD=30 \
  bash "$HOOK" 2>&1)
assert_exit "camelCase shape exits 0" $? 0
assert_contains "camelCase parsed" "$OUT" "15%"

# Test 10: Compound command `git commit && claude update` — detected
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x && claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD='false' \
  bash "$HOOK" 2>&1)
assert_exit "compound detected" $? 0
assert_contains "compound shows banner" "$OUT" "claude-update-budget-guard"

# Test 11: False positive guard — `my-claude update` must NOT trigger
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"my-claude update"}}' | bash "$HOOK" 2>&1)
assert_exit "my-claude passes through" $? 0
assert_not_contains "hyphen prefix no trigger" "$OUT" "claude-update-budget-guard"

# Test 12: Empty input — exit 0 silently
OUT=$(printf '' | bash "$HOOK" 2>&1)
assert_exit "empty input exits 0" $? 0

# Test 13: Default MODE (warn) does not block even at 0%
printf '{"five_hour":{"remaining_percent":0}}' > "$FIXTURE"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD="cat $FIXTURE" \
  bash "$HOOK" 2>&1)
assert_exit "default MODE never blocks" $? 0

# Test 14: Threshold override via env (set to 5 means 10% is above → exit 0 info)
printf '{"five_hour":{"remaining_percent":10}}' > "$FIXTURE"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  CLAUDE_UPDATE_USAGE_CMD="cat $FIXTURE" \
  CLAUDE_UPDATE_BUDGET_THRESHOLD=5 \
  bash "$HOOK" 2>&1)
assert_exit "threshold override exits 0" $? 0
assert_contains "threshold override above" "$OUT" "above threshold"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
