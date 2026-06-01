#!/bin/bash
# Tests for same-command-repeat-detector.sh
HOOK="examples/same-command-repeat-detector.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3', got: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3', got: $2)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

run_hook() {
    local sid="$1"
    local cmd="$2"
    local extra_env="${3:-}"
    local input
    input='{"tool_input": {"command": '"$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"'}}'
    # shellcheck disable=SC2086
    env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="$sid" $extra_env bash "$HOOK_ABS" 2>&1 <<< "$input"
}

# Test 1: First instance of a real command exits 0, no notice (streak = 1)
OUT=$(run_hook "s1" "npm run build"); RC=$?
assert_not_contains "first-real no block" "$OUT" "BLOCKED"
assert_exit "first-real exit 0" "$RC" "0"

# Test 2: Two different commands in a row — streak resets
OUT=$(run_hook "s2" "npm run build"); _=$?
OUT=$(run_hook "s2" "ls -la"); RC=$?
assert_not_contains "different cmd no notice" "$OUT" "NOTICE"
assert_exit "different cmd exit 0" "$RC" "0"

# Test 3: Second identical command → NOTICE 2/3, exit 0
OUT=$(run_hook "s3" "npm run build"); _=$?
OUT=$(run_hook "s3" "npm run build"); RC=$?
assert_contains "second-same notice" "$OUT" "NOTICE"
assert_contains "second-same 2/3" "$OUT" "2/3"
assert_exit "second-same exit 0" "$RC" "0"

# Test 4: Third identical command → BLOCKED, exit 2
OUT=$(run_hook "s4" "npm run build"); _=$?
OUT=$(run_hook "s4" "npm run build"); _=$?
OUT=$(run_hook "s4" "npm run build"); RC=$?
assert_contains "third-same blocked" "$OUT" "BLOCKED"
assert_contains "third-same mentions 25F" "$OUT" "25F"
assert_contains "third-same cites 63887" "$OUT" "63887"
assert_exit "third-same exit 2" "$RC" "2"

# Test 5: After block, a different command resets the streak
OUT=$(run_hook "s5" "npm run build"); _=$?
OUT=$(run_hook "s5" "npm run build"); _=$?
OUT=$(run_hook "s5" "npm test"); RC=$?  # different command
assert_not_contains "after-reset no block" "$OUT" "BLOCKED"
assert_exit "after-reset exit 0" "$RC" "0"

# Test 6: Whitespace canonicalisation — internal whitespace runs collapsed
OUT=$(run_hook "s6" "npm   run    build"); _=$?  # extra spaces
OUT=$(run_hook "s6" "npm run build"); RC=$?       # normal — should match
assert_contains "whitespace canon match" "$OUT" "2/3"
assert_exit "whitespace canon exit 0" "$RC" "0"

# Test 7: Leading/trailing whitespace stripped
OUT=$(run_hook "s7" "  npm run build  "); _=$?
OUT=$(run_hook "s7" "npm run build"); RC=$?
assert_contains "trim canon match" "$OUT" "2/3"
assert_exit "trim canon exit 0" "$RC" "0"

# Test 8: Short commands (< 4 chars) are not tracked
OUT=$(run_hook "s8" "ls"); _=$?
OUT=$(run_hook "s8" "ls"); _=$?
OUT=$(run_hook "s8" "ls"); RC=$?
assert_not_contains "short cmd no block" "$OUT" "BLOCKED"
assert_exit "short cmd exit 0" "$RC" "0"

# Test 9: Short command (pwd) not tracked
OUT=$(run_hook "s9" "pwd"); _=$?
OUT=$(run_hook "s9" "pwd"); _=$?
OUT=$(run_hook "s9" "pwd"); RC=$?
assert_exit "pwd short exit 0" "$RC" "0"

# Test 10: CC_SAME_CMD_REPEAT_DISABLE=1 — never block
OUT=$(run_hook "s10" "make build" "CC_SAME_CMD_REPEAT_DISABLE=1"); _=$?
OUT=$(run_hook "s10" "make build" "CC_SAME_CMD_REPEAT_DISABLE=1"); _=$?
OUT=$(run_hook "s10" "make build" "CC_SAME_CMD_REPEAT_DISABLE=1"); RC=$?
assert_not_contains "DISABLE no block" "$OUT" "BLOCKED"
assert_not_contains "DISABLE no notice" "$OUT" "NOTICE"
assert_exit "DISABLE exit 0" "$RC" "0"

# Test 11: CC_SAME_CMD_REPEAT_QUIET=1 — silent but still blocks
OUT=$(run_hook "s11" "make build" "CC_SAME_CMD_REPEAT_QUIET=1"); _=$?
OUT=$(run_hook "s11" "make build" "CC_SAME_CMD_REPEAT_QUIET=1"); _=$?
OUT=$(run_hook "s11" "make build" "CC_SAME_CMD_REPEAT_QUIET=1"); RC=$?
assert_not_contains "QUIET no message" "$OUT" "BLOCKED"
assert_exit "QUIET 3rd exit 2" "$RC" "2"

# Test 12: CC_SAME_CMD_REPEAT_THRESHOLD=2 — block at 2nd
OUT=$(run_hook "s12" "yarn dev" "CC_SAME_CMD_REPEAT_THRESHOLD=2"); _=$?
OUT=$(run_hook "s12" "yarn dev" "CC_SAME_CMD_REPEAT_THRESHOLD=2"); RC=$?
assert_contains "THRESHOLD=2 blocks 2nd" "$OUT" "BLOCKED"
assert_exit "THRESHOLD=2 exit 2" "$RC" "2"

# Test 13: CC_SAME_CMD_REPEAT_THRESHOLD=5 — does not block at 3rd
OUT=$(run_hook "s13" "yarn build" "CC_SAME_CMD_REPEAT_THRESHOLD=5"); _=$?
OUT=$(run_hook "s13" "yarn build" "CC_SAME_CMD_REPEAT_THRESHOLD=5"); _=$?
OUT=$(run_hook "s13" "yarn build" "CC_SAME_CMD_REPEAT_THRESHOLD=5"); RC=$?
assert_not_contains "THRESHOLD=5 no block at 3" "$OUT" "BLOCKED"
assert_exit "THRESHOLD=5 3rd exit 0" "$RC" "0"

# Test 14: Manual reset via "# RESET REPEAT" comment
OUT=$(run_hook "s14" "go build"); _=$?
OUT=$(run_hook "s14" "go build"); _=$?
OUT=$(run_hook "s14" "go build # RESET REPEAT"); _=$?  # reset
OUT=$(run_hook "s14" "go build"); RC=$?  # back to 1
assert_not_contains "post-reset no block" "$OUT" "BLOCKED"
assert_exit "post-reset exit 0" "$RC" "0"

# Test 15: Empty input handled (no command in JSON)
OUT=$(echo '{}' | env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="s15" bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "empty input exit 0" "$RC" "0"

# Test 16: Malformed JSON input handled
OUT=$(echo 'not json' | env TMPDIR="$TMPDIR" CLAUDE_SESSION_ID="s16" bash "$HOOK_ABS" 2>&1); RC=$?
assert_exit "malformed input exit 0" "$RC" "0"

# Test 17: Session isolation — same command in two different sessions shouldn't compound
OUT=$(run_hook "iso-a" "cargo build"); _=$?
OUT=$(run_hook "iso-a" "cargo build"); _=$?
OUT=$(run_hook "iso-b" "cargo build"); RC=$?  # different session, fresh streak
assert_not_contains "iso-b no block" "$OUT" "BLOCKED"
assert_exit "iso-b exit 0" "$RC" "0"

# Test 18: Long command truncation in block message (display only, detection unchanged)
LONG_CMD="docker run --rm -v /tmp:/tmp -e FOO=bar -e BAZ=qux -p 8080:80 --network host my-org/my-app:latest"
OUT=$(run_hook "s18" "$LONG_CMD"); _=$?
OUT=$(run_hook "s18" "$LONG_CMD"); _=$?
OUT=$(run_hook "s18" "$LONG_CMD"); RC=$?
assert_contains "long cmd block fires" "$OUT" "BLOCKED"
assert_contains "long cmd display truncated" "$OUT" "..."
assert_exit "long cmd block exit 2" "$RC" "2"

# Test 19: Command with newlines / multiline collapsed to single canonical form
OUT=$(run_hook "s19" "make
build"); _=$?
OUT=$(run_hook "s19" "make build"); RC=$?
assert_contains "newline collapse match" "$OUT" "2/3"
assert_exit "newline collapse exit 0" "$RC" "0"

# Test 20: Universal mitigation reference appears in block message
OUT=$(run_hook "s20" "npm install"); _=$?
OUT=$(run_hook "s20" "npm install"); _=$?
OUT=$(run_hook "s20" "npm install"); RC=$?
assert_contains "block mentions opus-4-7" "$OUT" "opus-4-7"
assert_exit "block exit 2" "$RC" "2"

# Test 21: Block message names anchor case
assert_contains "block mentions anchor" "$OUT" "63887"

# Test 22: Cluster 25 framing present in block message
assert_contains "block mentions cluster 25" "$OUT" "Cluster 25"

echo ""
echo "Results: $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ] || exit 1
