#!/bin/bash
# Tests for git-push-blast-radius-guard.sh
HOOK="examples/git-push-blast-radius-guard.sh"
# Allow running from /tmp during development: fall back to an absolute path.
[ -f "$HOOK" ] || HOOK="/tmp/ccps/git-push-blast-radius-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }

DIR="/tmp/cc-push-blast-test-$$"
export CC_PUSH_BLAST_DIR="$DIR"
export CC_PUSH_BLAST_WARN=3
export CC_PUSH_BLAST_BLOCK=6
export CC_PUSH_BLAST_WINDOW=3600

fresh() { rm -rf "$DIR"; }
# Build a Bash PreToolUse payload pushing to a named branch.
push() { printf '{"tool_name":"Bash","session_id":"%s","tool_input":{"command":"git push origin %s"}}' "$1" "$2"; }
# Record a push by actually running it through the hook (output discarded).
rec() { push "$1" "$2" | bash "$HOOK" >/dev/null 2>&1; }

# Test 1: non-Bash tool passes through silently
fresh
OUT=$(echo '{"tool_name":"WebFetch","tool_input":{"url":"https://x"}}' | bash "$HOOK" 2>&1)
assert_not_contains "non-Bash passthrough" "$OUT" "git-push-blast-radius-guard"
assert_not_contains "non-Bash no block" "$OUT" "decision"

# Test 2: a Bash command that is not a push passes through
fresh
OUT=$(echo '{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"git status"}}' | bash "$HOOK" 2>&1)
assert_not_contains "non-push passthrough" "$OUT" "git-push-blast-radius-guard"

# Test 3: first two distinct branches are silent (below WARN)
fresh
for b in b1 b2; do
  OUT=$(push s1 "$b" | bash "$HOOK" 2>&1)
  assert_not_contains "push $b silent" "$OUT" "git-push-blast-radius-guard"
done

# Test 4: at WARN (3rd distinct branch) -> stderr warning, no block
OUT=$(push s1 b3 | bash "$HOOK" 2>&1)
assert_contains "3rd distinct warns" "$OUT" "git-push-blast-radius-guard"
STDOUT=$(push s1 b4 | bash "$HOOK" 2>/dev/null)
assert_not_contains "4th no block on stdout" "$STDOUT" "decision"

# Test 5: at BLOCK (6th distinct) -> block decision JSON on stdout, exit 0
rec s1 b5
STDOUT=$(push s1 b6 | bash "$HOOK" 2>/dev/null)
RC=$?
assert_contains "6th distinct blocks" "$STDOUT" '"decision": "block"'
assert_contains "block reason references issue" "$STDOUT" "65944"
[ "$RC" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: block exits 0 (got $RC)"; }

# Test 6: re-pushing the SAME branch many times never trips (distinct stays 1)
fresh
for i in 1 2 3 4 5 6 7 8 9 10; do
  STDOUT=$(push s2 feature | bash "$HOOK" 2>/dev/null)
  assert_not_contains "re-push same branch #$i no block" "$STDOUT" "decision"
done

# Test 7: git push --all is an immediate trip (whole-repo fan-out)
fresh
STDOUT=$(echo '{"tool_name":"Bash","session_id":"s3","tool_input":{"command":"git push --all origin"}}' | bash "$HOOK" 2>/dev/null)
assert_contains "--all blocks immediately" "$STDOUT" '"decision": "block"'

# Test 8: off mode passes through even over the limit
fresh
for b in c1 c2 c3 c4 c5 c6; do rec s4 "$b"; done
OUT=$(push s4 c7 | CC_PUSH_BLAST_GUARD=off bash "$HOOK" 2>&1)
assert_not_contains "off mode no block" "$OUT" "decision"

# Test 9: warn mode never emits a block decision, only stderr
fresh
for b in d1 d2 d3 d4 d5; do rec s5 "$b"; done
OUT=$(push s5 d6 | CC_PUSH_BLAST_GUARD=warn bash "$HOOK" 2>&1)
assert_not_contains "warn mode no block decision" "$OUT" '"decision"'
assert_contains "warn mode warns" "$OUT" "git-push-blast-radius-guard"

# Test 10: window expiry prunes old branches -> count resets below warn
fresh
mkdir -p "$DIR"
OLD=$(( $(date +%s) - 7200 ))
for i in 1 2 3 4 5; do printf '%s\told%s\n' "$OLD" "$i" >> "$DIR/s6"; done
OUT=$(push s6 newbranch | bash "$HOOK" 2>&1)
assert_not_contains "expired window resets, no warn" "$OUT" "git-push-blast-radius-guard"

# Test 11: per-session isolation -- another session has its own counter
fresh
for b in e1 e2 e3 e4 e5 e6; do rec s7 "$b"; done   # s7 now blocking
STDOUT=$(push s8 e1 | bash "$HOOK" 2>/dev/null)
assert_not_contains "separate session not blocked" "$STDOUT" "decision"

# Test 12: malformed input fails open (no crash, no block)
fresh
OUT=$(echo 'not json' | bash "$HOOK" 2>&1)
assert_not_contains "malformed input fails open" "$OUT" "decision"

# Test 13: HEAD:branch refspec counts the destination branch
fresh
for i in 1 2 3 4 5; do rec s9 "f$i"; done
STDOUT=$(echo '{"tool_name":"Bash","session_id":"s9","tool_input":{"command":"git push origin HEAD:f6"}}' | bash "$HOOK" 2>/dev/null)
assert_contains "HEAD:dst counts destination -> blocks at 6th" "$STDOUT" '"decision": "block"'

# Test 14: pushing two branches in one command counts both
fresh
rec s10 g1
rec s10 g2
rec s10 g3
STDOUT=$(echo '{"tool_name":"Bash","session_id":"s10","tool_input":{"command":"git push origin g4 g5 g6"}}' | bash "$HOOK" 2>/dev/null)
assert_contains "multi-branch single push counts all -> blocks" "$STDOUT" '"decision": "block"'

rm -rf "$DIR"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
