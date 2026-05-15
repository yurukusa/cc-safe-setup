#!/bin/bash
# Tests for agent-sdk-credit-pool-monitor.sh
HOOK="examples/agent-sdk-credit-pool-monitor.sh"
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

# Use a per-test temp log so tests don't pollute the user's real log.
TMP_LOG=$(mktemp)
trap 'rm -f "$TMP_LOG"' EXIT

# Test 1: Non-Bash tool — silent pass-through.
OUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" bash "$HOOK" 2>&1)
assert_exit "non-Bash tool exits 0" $? 0
assert_not_contains "non-Bash has no banner" "$OUT" "agent-sdk-credit-pool-monitor"

# Test 2: Unrelated Bash command — silent pass-through.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" bash "$HOOK" 2>&1)
assert_exit "unrelated bash exits 0" $? 0
assert_not_contains "unrelated has no banner" "$OUT" "agent-sdk-credit-pool-monitor"

# Test 3: `claude -p summarize` — log an entry, exit 0, info message printed.
: > "$TMP_LOG"
OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"claude -p summarize"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" bash "$HOOK" 2>&1)
assert_exit "claude -p exits 0" $? 0
assert_contains "claude -p shows banner" "$OUT" "agent-sdk-credit-pool-monitor"
assert_contains "log contains one entry" "$(wc -l < "$TMP_LOG")" "1"

# Test 4: `claude --print ...` — same handling as `-p`.
: > "$TMP_LOG"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude --print review.md"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" bash "$HOOK" 2>&1)
assert_exit "claude --print exits 0" $? 0
assert_contains "claude --print logged" "$(wc -l < "$TMP_LOG")" "1"

# Test 5: QUIET mode suppresses informational message but still logs.
: > "$TMP_LOG"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p test"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" AGENT_SDK_QUIET="1" bash "$HOOK" 2>&1)
assert_exit "quiet mode exits 0" $? 0
assert_not_contains "quiet mode no info banner" "$OUT" "agent-sdk-credit-pool-monitor"
assert_contains "quiet mode still logs" "$(wc -l < "$TMP_LOG")" "1"

# Test 6: Threshold crossed → warning banner with response paths.
# 500 calls × $0.05 = $25 — over the $20 Pro ceiling.
: > "$TMP_LOG"
NOW=$(date +%s)
for i in $(seq 1 500); do
  printf '%s\t10\n' "$NOW" >> "$TMP_LOG"
done
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p again"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" bash "$HOOK" 2>&1)
assert_exit "threshold crossed exits 0" $? 0
assert_contains "threshold banner" "$OUT" "agent-sdk-credit-pool-monitor"
assert_contains "shows projection" "$OUT" "\$25"
assert_contains "shows response paths" "$OUT" "Migration Playbook"
assert_contains "shows Path D ref" "$OUT" "Kimi K2.5"

# Test 7: Hyphen prefix (false positive guard).
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"./my-claude -p hello"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" bash "$HOOK" 2>&1)
assert_exit "hyphen prefix exits 0" $? 0
assert_not_contains "hyphen prefix not detected" "$OUT" "agent-sdk-credit-pool-monitor"

# Test 8: Unknown tier emits warning and defaults to pro.
: > "$TMP_LOG"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p test"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="enterprise-custom" bash "$HOOK" 2>&1)
assert_exit "unknown tier exits 0" $? 0
assert_contains "unknown tier warns" "$OUT" "unknown AGENT_SDK_TIER"

# Test 9: Max20x tier — ceiling $200.
: > "$TMP_LOG"
NOW=$(date +%s)
for i in $(seq 1 3000); do
  printf '%s\t10\n' "$NOW" >> "$TMP_LOG"
done
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p test"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="max20x" bash "$HOOK" 2>&1)
assert_exit "max20x threshold exits 0" $? 0
assert_contains "max20x ceiling shown" "$OUT" "\$200"

# Test 10: Entries older than 30 days are filtered out (warning suppressed).
: > "$TMP_LOG"
OLD=$(($(date +%s) - 3000000))
for i in $(seq 1 500); do
  printf '%s\t10\n' "$OLD" >> "$TMP_LOG"
done
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p test"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" bash "$HOOK" 2>&1)
assert_exit "old entries filtered exits 0" $? 0
# Warning-only strings: "Response paths" appears only in the threshold-crossed warning.
assert_not_contains "old entries don't trigger warning" "$OUT" "Response paths"

# Test 11: Custom AVG_CALL_COST.
: > "$TMP_LOG"
NOW=$(date +%s)
for i in $(seq 1 100); do
  printf '%s\t10\n' "$NOW" >> "$TMP_LOG"
done
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p test"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" AGENT_SDK_AVG_CALL_COST="0.30" bash "$HOOK" 2>&1)
assert_exit "custom cost exits 0" $? 0
# 100 calls × $0.30 = $30 — over $20 Pro ceiling.
assert_contains "custom cost projection" "$OUT" "\$30"

# Test 12: Plain `claude` (no -p) — silent pass-through.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude resume"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" bash "$HOOK" 2>&1)
assert_exit "plain claude exits 0" $? 0
assert_not_contains "plain claude has no banner" "$OUT" "agent-sdk-credit-pool-monitor"

# Test 13: `claude update` — should not be detected as `-p`.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude update"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" bash "$HOOK" 2>&1)
assert_exit "claude update exits 0" $? 0
assert_not_contains "claude update no banner" "$OUT" "agent-sdk-credit-pool-monitor"

# Test 14: Custom warn threshold.
: > "$TMP_LOG"
NOW=$(date +%s)
for i in $(seq 1 100); do
  printf '%s\t10\n' "$NOW" >> "$TMP_LOG"
done
# 100 calls × $0.05 = $5 — 25% of $20 Pro ceiling.
# Default threshold is 75%; setting it to 20% should trigger warning.
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"claude -p test"}}' | \
  AGENT_SDK_LOG="$TMP_LOG" AGENT_SDK_TIER="pro" AGENT_SDK_WARN_THRESHOLD_PCT="20" bash "$HOOK" 2>&1)
assert_exit "low threshold exits 0" $? 0
assert_contains "low threshold triggers" "$OUT" "ceiling"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
