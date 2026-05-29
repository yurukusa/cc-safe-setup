#!/bin/bash
# Tests for bash-fanout-bounded-rewriter.sh
# Covers: 7 fan-out detection patterns, 5 safe-pass patterns,
# override / disable env toggles, suggested-rewrite content,
# fail-open on malformed input.

HOOK="examples/bash-fanout-bounded-rewriter.sh"
PASS=0 FAIL=0

run_hook() {
    local payload="$1"; shift
    env -u CC_BASH_FANOUT_DISABLE -u CC_BASH_FANOUT_OVERRIDE \
        -u CC_BASH_FANOUT_PARALLEL_BOUND \
        "$@" bash "$HOOK" <<< "$payload" 2>&1
    # bash exit status passes through; capture in caller via $?
}

assert_contains() { if echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -qF "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

run_and_capture() {
    local payload="$1"; shift
    env -u CC_BASH_FANOUT_DISABLE -u CC_BASH_FANOUT_OVERRIDE \
        -u CC_BASH_FANOUT_PARALLEL_BOUND \
        "$@" bash "$HOOK" <<< "$payload" 2>&1
    LAST_RC=$?
}

# Test 1: empty input — pass through
run_and_capture '{}'
assert_exit "empty input pass" "$LAST_RC" "0"

# Test 2: safe command (ls -la) — pass through silently
run_and_capture '{"tool_input":{"command":"ls -la"}}'
assert_exit "ls -la pass" "$LAST_RC" "0"

# Test 3: find -exec — blocked
run_and_capture '{"tool_input":{"command":"find . -name *.py -exec wc -l {} +"}}'
assert_exit "find -exec blocked" "$LAST_RC" "2"
OUT=$(run_hook '{"tool_input":{"command":"find . -name *.py -exec wc -l {} +"}}')
assert_contains "find -exec advisory" "$OUT" "Unbounded fan-out detected"
assert_contains "find -exec names pattern" "$OUT" "find ... -exec"
assert_contains "find -exec references #62193" "$OUT" "#62193"
assert_contains "find -exec suggests xargs -P rewrite" "$OUT" "xargs -0 -P 8"

# Test 4: for ... in $(...) — blocked
run_and_capture '{"tool_input":{"command":"for f in $(ls *.txt); do wc -l \"$f\"; done"}}'
assert_exit "for in dollar paren blocked" "$LAST_RC" "2"
OUT=$(run_hook '{"tool_input":{"command":"for f in $(ls *.txt); do wc -l \"$f\"; done"}}')
assert_contains "for advisory" "$OUT" "for ... in"

# Test 5: for in literal static list — pass through
run_and_capture '{"tool_input":{"command":"for i in 1 2 3; do echo $i; done"}}'
assert_exit "for in 1 2 3 pass" "$LAST_RC" "0"

# Test 6: for ... in $VAR — blocked
run_and_capture '{"tool_input":{"command":"for f in $FILES; do echo $f; done"}}'
assert_exit "for in dollar var blocked" "$LAST_RC" "2"

# Test 7: for ... in glob — blocked
run_and_capture '{"tool_input":{"command":"for f in *.log; do tail -1 $f; done"}}'
assert_exit "for in glob blocked" "$LAST_RC" "2"

# Test 8: while read — blocked
run_and_capture '{"tool_input":{"command":"cat list.txt | while read line; do process $line; done"}}'
assert_exit "while read blocked" "$LAST_RC" "2"
OUT=$(run_hook '{"tool_input":{"command":"cat list.txt | while read line; do process $line; done"}}')
assert_contains "while read advisory" "$OUT" "while read"

# Test 9: xargs without -P (serial xargs is safe) — pass through
run_and_capture '{"tool_input":{"command":"cat list.txt | xargs grep foo"}}'
assert_exit "xargs serial pass" "$LAST_RC" "0"

# Test 10: parallel without -j — blocked
run_and_capture '{"tool_input":{"command":"ls | parallel wc -l"}}'
assert_exit "parallel no -j blocked" "$LAST_RC" "2"
OUT=$(run_hook '{"tool_input":{"command":"ls | parallel wc -l"}}')
assert_contains "parallel advisory" "$OUT" "parallel"
assert_contains "parallel suggests -j" "$OUT" "parallel -j 8"

# Test 11: parallel -j 4 — pass through (already bounded)
run_and_capture '{"tool_input":{"command":"ls | parallel -j 4 wc -l"}}'
assert_exit "parallel -j N pass" "$LAST_RC" "0"

# Test 12: make -j (no number) — blocked
run_and_capture '{"tool_input":{"command":"make -j all"}}'
assert_exit "make -j blocked" "$LAST_RC" "2"
OUT=$(run_hook '{"tool_input":{"command":"make -j all"}}')
assert_contains "make -j advisory" "$OUT" "make -j without N"

# Test 13: make -j4 — pass through
run_and_capture '{"tool_input":{"command":"make -j4 all"}}'
assert_exit "make -j4 pass" "$LAST_RC" "0"

# Test 14: make -j 8 — pass through
run_and_capture '{"tool_input":{"command":"make -j 8 all"}}'
assert_exit "make -j 8 pass" "$LAST_RC" "0"

# Test 15: seq 1000 piped to while — blocked (while-read pattern fires first, which is the correct earlier-pattern preemption)
run_and_capture '{"tool_input":{"command":"seq 1000 | while read i; do echo $i; done"}}'
assert_exit "seq 1000 to while blocked" "$LAST_RC" "2"
OUT=$(run_hook '{"tool_input":{"command":"seq 1000 | while read i; do echo $i; done"}}')
assert_contains "seq+while-read pattern names while" "$OUT" "while read"

# Test 15b: seq 1000 piped to xargs serial — pattern 7 fires (no while-read precursor)
# Note: seq + xargs is actually serial xargs (no -P), so it passes through.
# To test pattern 7 in isolation we need a high-N seq without earlier-matching patterns.
# An unusual but valid case: seq 1000 piped directly to a parallel command.
run_and_capture '{"tool_input":{"command":"seq 1000 | parallel echo"}}'
# This hits parallel-without-j pattern first.
assert_exit "seq 1000 to parallel blocked" "$LAST_RC" "2"

# Test 16: seq 5 piped to while — pass through (N <= 100)
run_and_capture '{"tool_input":{"command":"seq 5 | while read i; do echo $i; done"}}'
# Note: this one will hit while read pattern first; let's verify
# The 'while read' check is earlier than seq, so seq is unreachable for low N.
# But the while-read check is still active. Both should result in block.
assert_exit "seq 5 to while still blocked by while pattern" "$LAST_RC" "2"

# Test 17: seq 5 piped to xargs — pass through (serial xargs)
run_and_capture '{"tool_input":{"command":"seq 5 | xargs echo"}}'
assert_exit "seq 5 to xargs pass" "$LAST_RC" "0"

# Test 18: DISABLE env suppresses all checks
run_and_capture '{"tool_input":{"command":"find . -exec rm {} +"}}' CC_BASH_FANOUT_DISABLE=1
assert_exit "disable env pass" "$LAST_RC" "0"

# Test 19: OVERRIDE env allows one fan-out call
run_and_capture '{"tool_input":{"command":"find . -exec rm {} +"}}' CC_BASH_FANOUT_OVERRIDE=1
assert_exit "override env pass" "$LAST_RC" "0"

# Test 20: PARALLEL_BOUND env changes suggested rewrite
OUT=$(run_hook '{"tool_input":{"command":"find . -exec rm {} +"}}' CC_BASH_FANOUT_PARALLEL_BOUND=4)
assert_contains "custom bound 4 in rewrite" "$OUT" "xargs -0 -P 4"

# Test 21: malformed JSON — fail-open
run_and_capture 'not-json'
assert_exit "malformed input pass" "$LAST_RC" "0"

# Test 22: missing tool_input — fail-open
run_and_capture '{"other":"field"}'
assert_exit "missing tool_input pass" "$LAST_RC" "0"

# Test 23: empty command — fail-open
run_and_capture '{"tool_input":{"command":""}}'
assert_exit "empty command pass" "$LAST_RC" "0"

# Test 24: advisory references PreToolUse layer vs cgroup
OUT=$(run_hook '{"tool_input":{"command":"find . -exec rm {} +"}}')
assert_contains "advisory names cgroup layer" "$OUT" "cgroup TasksMax"
assert_contains "advisory explains layer choice" "$OUT" "rendering the tool useless"
assert_contains "advisory gives override path" "$OUT" "CC_BASH_FANOUT_OVERRIDE=1"

# Test 25: regular git commands pass through
run_and_capture '{"tool_input":{"command":"git status"}}'
assert_exit "git status pass" "$LAST_RC" "0"
run_and_capture '{"tool_input":{"command":"git log --oneline -10"}}'
assert_exit "git log pass" "$LAST_RC" "0"

# Test 26: rm without fan-out passes through (deny is a different hook's job)
run_and_capture '{"tool_input":{"command":"rm /tmp/file.txt"}}'
assert_exit "rm simple pass" "$LAST_RC" "0"

# Test 27: xargs -P 4 — pass through (already bounded)
run_and_capture '{"tool_input":{"command":"cat list.txt | xargs -P 4 -n 1 process"}}'
assert_exit "xargs -P 4 pass" "$LAST_RC" "0"

# Test 28: find without -exec — pass through (find itself is fine)
run_and_capture '{"tool_input":{"command":"find . -name *.py"}}'
assert_exit "find without exec pass" "$LAST_RC" "0"

# Test 29: find piped to xargs -P — pass through
run_and_capture '{"tool_input":{"command":"find . -name *.py -print0 | xargs -0 -P 8 wc -l"}}'
assert_exit "find piped to xargs -P pass" "$LAST_RC" "0"

# Test 30: error message contains all four required sections
OUT=$(run_hook '{"tool_input":{"command":"find . -exec rm {} +"}}')
assert_contains "error has detection block" "$OUT" "Unbounded fan-out detected"
assert_contains "error has rewrite block" "$OUT" "Bounded rewrite:"
assert_contains "error has override path" "$OUT" "Override for this one call"
assert_contains "error has disable path" "$OUT" "Disable entirely"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] && exit 0 || exit 1
