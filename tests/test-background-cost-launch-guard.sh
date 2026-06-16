#!/bin/bash
# Tests for background-cost-launch-guard.sh
HOOK="$(dirname "$0")/../examples/background-cost-launch-guard.sh"
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

# Run the hook with a JSON payload, return its exit code.
run_hook() {
  printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

echo "Testing background-cost-launch-guard.sh"
echo "======================================="

# 1. background + Anthropic batch API → block (exit 2)
EXIT=$(run_hook '{"tool_input":{"command":"python run_batch.py --endpoint https://api.anthropic.com/v1/messages/batches","run_in_background":true}}')
[ "$EXIT" = "2" ] && run_test "bg + anthropic batch → block" pass || run_test "bg + anthropic batch → block (got $EXIT)" fail

# 2. background + loop over claude -p → block
EXIT=$(run_hook '{"tool_input":{"command":"for f in *.txt; do claude -p summarize < $f; done","run_in_background":true}}')
[ "$EXIT" = "2" ] && run_test "bg + loop claude -p → block" pass || run_test "bg + loop claude -p → block (got $EXIT)" fail

# 3. background + curl openai in a while loop → block
EXIT=$(run_hook '{"tool_input":{"command":"while true; do curl https://api.openai.com/v1/chat/completions -d @p.json; done","run_in_background":true}}')
[ "$EXIT" = "2" ] && run_test "bg + curl openai loop → block" pass || run_test "bg + curl openai loop → block (got $EXIT)" fail

# 4. background + dev server (no cost signature) → pass (exit 0)
EXIT=$(run_hook '{"tool_input":{"command":"npm run dev","run_in_background":true}}')
[ "$EXIT" = "0" ] && run_test "bg + npm run dev → pass" pass || run_test "bg + npm run dev → pass (got $EXIT)" fail

# 5. background + log tail → pass
EXIT=$(run_hook '{"tool_input":{"command":"tail -f /var/log/app.log","run_in_background":true}}')
[ "$EXIT" = "0" ] && run_test "bg + tail -f log → pass" pass || run_test "bg + tail -f log → pass (got $EXIT)" fail

# 6. foreground + cost command → pass (only background launches are this hook's concern)
EXIT=$(run_hook '{"tool_input":{"command":"python run_batch.py --endpoint https://api.anthropic.com/v1/messages","run_in_background":false}}')
[ "$EXIT" = "0" ] && run_test "foreground cost cmd → pass" pass || run_test "foreground cost cmd → pass (got $EXIT)" fail

# 7. run_in_background field absent (defaults false) → pass
EXIT=$(run_hook '{"tool_input":{"command":"curl https://api.anthropic.com/v1/messages"}}')
[ "$EXIT" = "0" ] && run_test "no run_in_background field → pass" pass || run_test "no run_in_background field → pass (got $EXIT)" fail

# 8. empty input → fail open (exit 0)
EXIT=$(run_hook '{}')
[ "$EXIT" = "0" ] && run_test "empty input → exit 0" pass || run_test "empty input → exit 0 (got $EXIT)" fail

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
