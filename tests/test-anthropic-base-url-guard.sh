#!/bin/bash
# Tests for anthropic-base-url-guard.sh
HOOK="$(dirname "$0")/../examples/anthropic-base-url-guard.sh"
PASS=0 FAIL=0

run_test() {
  local desc="$1" expected_exit="$2"
  shift 2
  # Run with remaining env vars
  local actual_exit
  echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | env "$@" bash "$HOOK" >/dev/null 2>/dev/null
  actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    ((FAIL++))
  fi
}

echo "Testing anthropic-base-url-guard.sh"
echo "===================================="

# 1. Default URL (not set) — should pass
run_test "default URL (unset) passes" 0 ANTHROPIC_BASE_URL=""

# 2. Official API URL — should pass
run_test "official api.anthropic.com passes" 0 ANTHROPIC_BASE_URL="https://api.anthropic.com"

# 3. Official with path — should pass
run_test "official URL with path passes" 0 ANTHROPIC_BASE_URL="https://api.anthropic.com/v1"

# 4. Localhost — warn mode (exit 0)
run_test "localhost warns but passes (default action=warn)" 0 \
  ANTHROPIC_BASE_URL="http://localhost:4010" CC_BASE_URL_ACTION="warn"

# 5. Localhost — block mode (exit 2)
run_test "localhost blocks when action=block" 2 \
  ANTHROPIC_BASE_URL="http://localhost:4010" CC_BASE_URL_ACTION="block"

# 6. Custom proxy — block mode
run_test "custom proxy blocks" 2 \
  ANTHROPIC_BASE_URL="http://192.168.1.100:8080" CC_BASE_URL_ACTION="block"

# 7. Allowlisted custom URL — should pass
run_test "allowlisted custom URL passes" 0 \
  ANTHROPIC_BASE_URL="https://proxy.corp.com/anthropic" \
  CC_ALLOWED_BASE_URLS="https://api.anthropic.com,https://proxy.corp.com/anthropic"

# 8. Non-allowlisted with custom allowlist — block
run_test "non-allowlisted URL blocks" 2 \
  ANTHROPIC_BASE_URL="http://localhost:4010" \
  CC_ALLOWED_BASE_URLS="https://api.anthropic.com,https://proxy.corp.com" \
  CC_BASE_URL_ACTION="block"

# 9. Empty ANTHROPIC_BASE_URL treated as default — pass
run_test "empty string treated as default" 0 ANTHROPIC_BASE_URL=""

# 10. HTTPS localhost still suspicious — block
run_test "https localhost still blocks" 2 \
  ANTHROPIC_BASE_URL="https://localhost:4010" CC_BASE_URL_ACTION="block"

# 11. Log file creation
TMPLOG="/tmp/test-base-url-guard-$$.log"
echo '{"tool_name":"Bash"}' | env ANTHROPIC_BASE_URL="http://evil:1234" CC_BASE_URL_LOG="$TMPLOG" CC_BASE_URL_ACTION="warn" bash "$HOOK" >/dev/null 2>/dev/null
if [ -f "$TMPLOG" ] && grep -q "evil:1234" "$TMPLOG"; then
  echo "  PASS: log file created with violation"
  ((PASS++))
else
  echo "  FAIL: log file not created or missing content"
  ((FAIL++))
fi
rm -f "$TMPLOG"

# 12. Warn mode outputs to stderr
OUTPUT=$(echo '{"tool_name":"Bash"}' | env ANTHROPIC_BASE_URL="http://localhost:4010" CC_BASE_URL_ACTION="warn" bash "$HOOK" 2>&1 >/dev/null)
if echo "$OUTPUT" | grep -q "WARNING"; then
  echo "  PASS: warn mode outputs warning to stderr"
  ((PASS++))
else
  echo "  FAIL: warn mode did not output warning"
  ((FAIL++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL))"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
