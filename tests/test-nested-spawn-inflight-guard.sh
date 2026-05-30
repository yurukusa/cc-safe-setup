#!/bin/bash
# Tests for nested-spawn-inflight-guard.sh
HOOK="$(dirname "$0")/../examples/nested-spawn-inflight-guard.sh"
PASS=0
FAIL=0

mktempd() {
  mktemp -d "${TMPDIR:-/tmp}/cc-nested-spawn-test.XXXXXX"
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

# Build a transcript file with N in-flight Task dispatches.
# Args: $1=output_path  $2=count_of_dispatched  $3=count_of_resolved
mk_transcript() {
  local path="$1"
  local dispatched="$2"
  local resolved="$3"
  : > "$path"
  local i=0
  while [ "$i" -lt "$dispatched" ]; do
    printf '{"message":{"content":[{"type":"tool_use","id":"toolu_%03d","name":"Task","input":{"description":"d"}}]}}\n' "$i" >> "$path"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$resolved" ]; do
    printf '{"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_%03d","content":"done"}]}}\n' "$i" >> "$path"
    i=$((i + 1))
  done
}

echo "Testing nested-spawn-inflight-guard.sh"
echo "======================================"

# Test 1: non-dispatcher tool (Bash) → silent exit 0
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 10 0
EXIT=0
echo "{\"tool_name\":\"Bash\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "non-dispatcher tool name → exit 0" pass || run_test "non-dispatcher tool name → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 2: non-dispatcher tool (Read) → silent exit 0
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 10 0
echo "{\"tool_name\":\"Read\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "Read tool → exit 0" pass || run_test "Read tool → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 3: missing transcript_path → fail open exit 0
echo '{"tool_name":"Task"}' | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "missing transcript_path → fail open exit 0" pass || run_test "missing transcript_path → fail open exit 0 (got $EXIT)" fail

# Test 4: unreadable transcript_path → fail open exit 0
echo '{"tool_name":"Task","transcript_path":"/nonexistent/path.jsonl"}' | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "unreadable transcript → fail open exit 0" pass || run_test "unreadable transcript → fail open exit 0 (got $EXIT)" fail

# Test 5: CC_NESTED_SPAWN_DISABLE=1 → bypass even when budget exceeded
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 20 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | CC_NESTED_SPAWN_DISABLE=1 bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "CC_NESTED_SPAWN_DISABLE=1 bypasses budget" pass || run_test "CC_NESTED_SPAWN_DISABLE=1 bypasses budget (got $EXIT)" fail
rm -rf "$TD"

# Test 6: CC_NESTED_SPAWN_OVERRIDE=1 → bypass even when budget exceeded
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 20 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | CC_NESTED_SPAWN_OVERRIDE=1 bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "CC_NESTED_SPAWN_OVERRIDE=1 bypasses budget" pass || run_test "CC_NESTED_SPAWN_OVERRIDE=1 bypasses budget (got $EXIT)" fail
rm -rf "$TD"

# Test 7: zero in-flight (5 dispatched, 5 resolved) → exit 0
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 5 5
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "zero in-flight (5d/5r) → exit 0" pass || run_test "zero in-flight (5d/5r) → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 8: 3 in-flight (5 dispatched, 2 resolved), budget 5 → exit 0
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 5 2
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "3 in-flight below budget 5 → exit 0" pass || run_test "3 in-flight below budget 5 → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 9: 5 in-flight (5 dispatched, 0 resolved), budget 5 → exit 2 (at budget)
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 5 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "5 in-flight at budget 5 → exit 2" pass || run_test "5 in-flight at budget 5 → exit 2 (got $EXIT)" fail
rm -rf "$TD"

# Test 10: 7 in-flight, budget 5 → exit 2 (above budget)
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 7 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "7 in-flight above budget 5 → exit 2" pass || run_test "7 in-flight above budget 5 → exit 2 (got $EXIT)" fail
rm -rf "$TD"

# Test 11: custom budget via env var (CC_NESTED_SPAWN_BUDGET=3, 4 in-flight) → exit 2
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 4 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | CC_NESTED_SPAWN_BUDGET=3 bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "custom budget 3, 4 in-flight → exit 2" pass || run_test "custom budget 3, 4 in-flight → exit 2 (got $EXIT)" fail
rm -rf "$TD"

# Test 12: custom budget allows more (budget=10, 7 in-flight) → exit 0
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 7 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | CC_NESTED_SPAWN_BUDGET=10 bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "custom budget 10, 7 in-flight → exit 0" pass || run_test "custom budget 10, 7 in-flight → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 13: legacy "Agent" tool name matched
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4; do
  printf '{"message":{"content":[{"type":"tool_use","id":"toolu_a%d","name":"Agent","input":{}}]}}\n' "$i" >> "$TX"
done
echo "{\"tool_name\":\"Agent\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "legacy Agent tool name → tracked" pass || run_test "legacy Agent tool name → tracked (got $EXIT)" fail
rm -rf "$TD"

# Test 14: SendMessage tool name matched
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4; do
  printf '{"message":{"content":[{"type":"tool_use","id":"toolu_s%d","name":"SendMessage","input":{}}]}}\n' "$i" >> "$TX"
done
echo "{\"tool_name\":\"SendMessage\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "SendMessage tool name → tracked" pass || run_test "SendMessage tool name → tracked (got $EXIT)" fail
rm -rf "$TD"

# Test 15: mixed tool calls (Task + Bash) — only Task counted
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4 5 6 7 8 9; do
  # 10 Bash calls — should not count
  printf '{"message":{"content":[{"type":"tool_use","id":"toolu_b%d","name":"Bash","input":{}}]}}\n' "$i" >> "$TX"
done
for i in 0 1; do
  # 2 Task calls — under budget
  printf '{"message":{"content":[{"type":"tool_use","id":"toolu_t%d","name":"Task","input":{}}]}}\n' "$i" >> "$TX"
done
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "mixed tool calls — only Task family counted" pass || run_test "mixed tool calls — only Task family counted (got $EXIT)" fail
rm -rf "$TD"

# Test 16: malformed JSON in transcript → fail open (exit 0)
TD=$(mktempd); TX="$TD/t.jsonl"
echo "not valid json" > "$TX"
echo "this is also broken {" >> "$TX"
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "malformed transcript → fail open" pass || run_test "malformed transcript → fail open (got $EXIT)" fail
rm -rf "$TD"

# Test 17: advisory message names budget and in-flight ids
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 6 0
STDERR=$(echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" 2>&1 >/dev/null)
EXIT_NAMED=0
echo "$STDERR" | grep -q "BLOCKED: 6 subagent" || EXIT_NAMED=1
echo "$STDERR" | grep -q "budget: 5" || EXIT_NAMED=1
echo "$STDERR" | grep -q "toolu_000" || EXIT_NAMED=1
echo "$STDERR" | grep -q "CC_NESTED_SPAWN_OVERRIDE" || EXIT_NAMED=1
[ "$EXIT_NAMED" = "0" ] && run_test "advisory names count, budget, ids, override path" pass || run_test "advisory names count, budget, ids, override path (missing fields)" fail
rm -rf "$TD"

# Test 18: non-numeric budget → fail open
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 10 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | CC_NESTED_SPAWN_BUDGET=abc bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "non-numeric budget → fail open" pass || run_test "non-numeric budget → fail open (got $EXIT)" fail
rm -rf "$TD"

# Test 19: tool_use_id reuse — last write wins (in-flight only if no later result)
# 3 dispatched (id 0..2), then 2 resolved (id 0,1), id 2 still in-flight → 1 in-flight, budget 5 → pass
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 3 2
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "3 dispatched / 2 resolved → 1 in-flight → exit 0" pass || run_test "3 dispatched / 2 resolved → 1 in-flight → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 20: LOOKBACK truncation does not over-count old completed work
# Old work has 100 dispatched + 100 resolved early in the file; only last 10 lines visible
# In the visible window: 5 dispatched, 0 resolved → 5 in-flight, budget 5 → exit 2
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4 5 6 7 8 9; do
  printf '{"message":{"content":[{"type":"tool_use","id":"old_%d","name":"Task","input":{}}]}}\n' "$i" >> "$TX"
  printf '{"message":{"content":[{"type":"tool_result","tool_use_id":"old_%d","content":"d"}]}}\n' "$i" >> "$TX"
done
for i in 100 101 102 103 104; do
  printf '{"message":{"content":[{"type":"tool_use","id":"recent_%d","name":"Task","input":{}}]}}\n' "$i" >> "$TX"
done
# LOOKBACK=5 makes only the last 5 lines visible — all 5 are recent_* tool_use entries.
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | CC_NESTED_SPAWN_LOOKBACK=5 bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "LOOKBACK=5 sees only recent 5 in-flight → exit 2" pass || run_test "LOOKBACK=5 sees only recent 5 in-flight → exit 2 (got $EXIT)" fail
rm -rf "$TD"

# Test 21: tool family in MCP-style entries (alternate transcript shape: bare tool_use object, no message wrapper)
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4; do
  printf '{"type":"tool_use","id":"bare_%d","name":"Task","input":{}}\n' "$i" >> "$TX"
done
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "bare tool_use shape (no message wrapper) → tracked" pass || run_test "bare tool_use shape (no message wrapper) → tracked (got $EXIT)" fail
rm -rf "$TD"

# Test 22: tool_name with unrelated name like "TaskComplete" must NOT match "Task" prefix
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4 5 6 7 8 9; do
  printf '{"message":{"content":[{"type":"tool_use","id":"tc_%d","name":"TaskComplete","input":{}}]}}\n' "$i" >> "$TX"
done
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "TaskComplete (different tool) not counted as Task" pass || run_test "TaskComplete (different tool) not counted as Task (got $EXIT)" fail
rm -rf "$TD"

# Test 23: tool_name with case mismatch ("task" lowercase) must NOT match (exact case)
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
for i in 0 1 2 3 4; do
  printf '{"message":{"content":[{"type":"tool_use","id":"lc_%d","name":"task","input":{}}]}}\n' "$i" >> "$TX"
done
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "lowercase 'task' (case mismatch) not counted" pass || run_test "lowercase 'task' (case mismatch) not counted (got $EXIT)" fail
rm -rf "$TD"

# Test 24: assistant turn with multiple tool_use in one content array (parallel dispatch)
TD=$(mktempd); TX="$TD/t.jsonl"
: > "$TX"
# One assistant turn that dispatches 6 Task calls in parallel
printf '{"message":{"content":[' >> "$TX"
for i in 0 1 2 3 4 5; do
  [ "$i" -gt 0 ] && printf ',' >> "$TX"
  printf '{"type":"tool_use","id":"par_%d","name":"Task","input":{}}' "$i" >> "$TX"
done
printf ']}}\n' >> "$TX"
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "2" ] && run_test "single turn with 6 parallel Task dispatches → exit 2" pass || run_test "single turn with 6 parallel Task dispatches → exit 2 (got $EXIT)" fail
rm -rf "$TD"

# Test 25: empty transcript file (zero lines) → no in-flight → exit 0
TD=$(mktempd); TX="$TD/t.jsonl"; : > "$TX"
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "empty transcript → 0 in-flight → exit 0" pass || run_test "empty transcript → 0 in-flight → exit 0 (got $EXIT)" fail
rm -rf "$TD"

# Test 26: 4 in-flight default budget 5 → still safe (exit 0)
TD=$(mktempd); TX="$TD/t.jsonl"; mk_transcript "$TX" 4 0
echo "{\"tool_name\":\"Task\",\"transcript_path\":\"$TX\"}" | bash "$HOOK" >/dev/null 2>&1
EXIT=$?
[ "$EXIT" = "0" ] && run_test "4 in-flight under default budget 5 → exit 0" pass || run_test "4 in-flight under default budget 5 → exit 0 (got $EXIT)" fail
rm -rf "$TD"

echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
