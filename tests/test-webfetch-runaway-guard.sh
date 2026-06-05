#!/bin/bash
# Tests for webfetch-runaway-guard.sh
HOOK="examples/webfetch-runaway-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

DIR="/tmp/cc-webfetch-runaway-test-$$"
export CC_WEBFETCH_RUNAWAY_DIR="$DIR"
export CC_WEBFETCH_RUNAWAY_WARN=3
export CC_WEBFETCH_RUNAWAY_BLOCK=5
export CC_WEBFETCH_RUNAWAY_WINDOW=300

fresh() { rm -rf "$DIR"; }
WF='{"tool_name":"WebFetch","session_id":"s1","tool_input":{"url":"https://example.com/'

# Test 1: non-WebFetch tool passes through silently
fresh
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$HOOK" 2>&1)
assert_not_contains "non-WebFetch passthrough" "$OUT" "webfetch-runaway-guard"
assert_not_contains "non-WebFetch no block" "$OUT" "decision"

# Test 2-3: first fetches below WARN are silent
fresh
for i in 1 2; do
  OUT=$(echo "${WF}${i}\"}}" | bash "$HOOK" 2>&1)
  assert_not_contains "fetch $i silent" "$OUT" "webfetch-runaway-guard"
done

# Test 4: at WARN threshold (3rd) → stderr warning, no block, exit 0
OUT=$(echo "${WF}3\"}}" | bash "$HOOK" 2>/tmp/wf-err-$$; cat /tmp/wf-err-$$)
RC=$?
assert_contains "3rd warns" "$OUT" "webfetch-runaway-guard"
OUTSTDOUT=$(echo "${WF}4\"}}" | bash "$HOOK" 2>/dev/null)
assert_not_contains "4th no block on stdout" "$OUTSTDOUT" "decision"

# Test 5: at BLOCK threshold (5th) → block decision JSON on stdout, exit 0
STDOUT=$(echo "${WF}5\"}}" | bash "$HOOK" 2>/dev/null)
RC=$?
assert_contains "5th blocks" "$STDOUT" '"decision": "block"'
assert_contains "block reason references issue" "$STDOUT" "65684"
[ "$RC" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: block exits 0 (got $RC)"; }

# Test 6: off mode passes through even when over the limit
OUT=$(CC_WEBFETCH_RUNAWAY_GUARD=off bash -c "echo '${WF}9\"}}' | bash '$HOOK'" 2>&1)
assert_not_contains "off mode no block" "$OUT" "decision"
assert_not_contains "off mode no warn" "$OUT" "webfetch-runaway-guard"

# Test 7: warn mode never emits a block decision, only stderr
OUT=$(CC_WEBFETCH_RUNAWAY_GUARD=warn bash -c "echo '${WF}9\"}}' | bash '$HOOK'" 2>&1)
assert_not_contains "warn mode no block decision" "$OUT" '"decision"'
assert_contains "warn mode warns" "$OUT" "webfetch-runaway-guard"

# Test 8: window expiry prunes old timestamps → count resets below warn
fresh
mkdir -p "$DIR"
# Seed 10 timestamps that are older than the window (now-400s)
OLD=$(( $(date +%s) - 400 ))
for i in $(seq 1 10); do echo "$OLD" >> "$DIR/s1"; done
OUT=$(echo "${WF}1\"}}" | bash "$HOOK" 2>&1)
assert_not_contains "expired window resets, no warn" "$OUT" "webfetch-runaway-guard"

# Test 9: per-session isolation — a different session has its own counter
fresh
for i in 1 2 3 4 5; do echo "${WF}${i}\"}}" | bash "$HOOK" >/dev/null 2>&1; done   # s1 now at block
OUT=$(echo '{"tool_name":"WebFetch","session_id":"s2","tool_input":{"url":"https://example.com/a"}}' | bash "$HOOK" 2>&1)
assert_not_contains "separate session not blocked" "$OUT" "decision"

# Test 10: malformed input fails open (no crash, no block)
fresh
OUT=$(echo 'not json' | bash "$HOOK" 2>&1)
assert_not_contains "malformed input fails open" "$OUT" "decision"

rm -rf "$DIR" /tmp/wf-err-$$
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
