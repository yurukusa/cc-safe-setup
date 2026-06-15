#!/bin/bash
# Tests for deployment-readback-gate.sh
HOOK="$(dirname "$0")/../examples/deployment-readback-gate.sh"
PASS=0 FAIL=0

TEST_STATE_DIR=$(mktemp -d -t readback-test-XXXXXX)
trap 'rm -rf "$TEST_STATE_DIR"' EXIT

run_test() {
  local desc="$1" expected_exit="$2" input="$3"
  printf '%s' "$input" | env CC_READBACK_RECEIPT_DIR="$TEST_STATE_DIR" bash "$HOOK" >/dev/null 2>/dev/null
  local actual_exit=$?
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"; FAIL=$((FAIL+1))
  fi
}

# Not-applicable inputs must pass through (exit 0) — repo convention for hooks.
run_test "not-applicable: empty JSON {} exits 0" 0 '{}'
run_test "not-applicable: empty string exits 0" 0 ''
run_test "not-applicable: unrelated tool input exits 0" 0 '{"tool_input":{"command":"ls"}}'

# Fresh, matching, success -> allow (exit 0). readback 2s before claim, window 300s.
run_test "allow: fresh + matching + success" 0 '{
  "claim_span":"deployment complete for api@abc123","claim_time":"2026-06-16T03:40:00.000Z",
  "claimed_ref":"abc123","authority":"github_deployments_api",
  "queried_ref":"abc123","queried_state":"success","readback_time":"2026-06-16T03:39:58.000Z",
  "stale_if_older_than_ms":300000 }'

# ref mismatch -> refuse-mismatch (exit 2)
run_test "refuse-mismatch: ref differs" 2 '{
  "claim_time":"2026-06-16T03:40:00.000Z","claimed_ref":"abc123","authority":"gh",
  "queried_ref":"def456","queried_state":"success","readback_time":"2026-06-16T03:39:58.000Z",
  "stale_if_older_than_ms":300000 }'

# state not success -> refuse-mismatch (exit 2)
run_test "refuse-mismatch: state failure" 2 '{
  "claim_time":"2026-06-16T03:40:00.000Z","claimed_ref":"abc123","authority":"gh",
  "queried_ref":"abc123","queried_state":"failure","readback_time":"2026-06-16T03:39:58.000Z",
  "stale_if_older_than_ms":300000 }'

# explicit query-failure -> refuse-query-failure (exit 2), fail closed
run_test "refuse-query-failure: authority unreachable" 2 '{
  "claim_time":"2026-06-16T03:40:00.000Z","claimed_ref":"abc123","authority":"gh",
  "queried_ref":"","queried_state":"query-failure","readback_time":"2026-06-16T03:39:58.000Z",
  "stale_if_older_than_ms":300000 }'

# stale readback (1 hour older than claim, window 300s) -> refuse-stale (exit 2)
run_test "refuse-stale: readback older than window" 2 '{
  "claim_time":"2026-06-16T03:40:00.000Z","claimed_ref":"abc123","authority":"gh",
  "queried_ref":"abc123","queried_state":"success","readback_time":"2026-06-16T02:40:00.000Z",
  "stale_if_older_than_ms":300000 }'

# missing required field (authority) -> fail closed (exit 2)
run_test "fail-closed: missing authority" 2 '{
  "claim_time":"2026-06-16T03:40:00.000Z","claimed_ref":"abc123",
  "queried_ref":"abc123","queried_state":"success","readback_time":"2026-06-16T03:39:58.000Z",
  "stale_if_older_than_ms":300000 }'

# unparseable timestamp -> fail closed (exit 2)
run_test "fail-closed: unparseable claim_time" 2 '{
  "claim_time":"not-a-date","claimed_ref":"abc123","authority":"gh",
  "queried_ref":"abc123","queried_state":"success","readback_time":"2026-06-16T03:39:58.000Z",
  "stale_if_older_than_ms":300000 }'

# readback AFTER claim (negative age) is fresh -> allow (exit 0)
run_test "allow: readback after claim (negative age)" 0 '{
  "claim_time":"2026-06-16T03:40:00.000Z","claimed_ref":"abc123","authority":"gh",
  "queried_ref":"abc123","queried_state":"success","readback_time":"2026-06-16T03:40:05.000Z",
  "stale_if_older_than_ms":300000 }'

# A receipt file should have been written for each call (8 calls).
RECEIPTS=$(find "$TEST_STATE_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$RECEIPTS" -ge 8 ]; then
  echo "  PASS: receipt written per call (count=$RECEIPTS)"; PASS=$((PASS+1))
else
  echo "  FAIL: receipt count (expected >=8, got $RECEIPTS)"; FAIL=$((FAIL+1))
fi

# The allow receipt should record decision=allow.
ALLOW_RECEIPTS=$(grep -lE '"decision": *"allow"' "$TEST_STATE_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$ALLOW_RECEIPTS" -ge 2 ]; then
  echo "  PASS: allow decisions recorded in receipts (count=$ALLOW_RECEIPTS)"; PASS=$((PASS+1))
else
  echo "  FAIL: allow receipts (expected >=2, got $ALLOW_RECEIPTS)"; FAIL=$((FAIL+1))
fi

echo ""
echo "deployment-readback-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
