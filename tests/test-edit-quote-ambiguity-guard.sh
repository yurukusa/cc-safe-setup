#!/bin/bash
# Tests for edit-quote-ambiguity-guard.sh
# Absolute path: tests build scratch files under TMPDIR.
HOOK="$(cd "$(dirname "$0")/../examples" && pwd)/edit-quote-ambiguity-guard.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1" result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"; FAIL=$((FAIL + 1))
  fi
}

D=$(mktemp -d "${TMPDIR:-/tmp}/cc-quote-guard-test.XXXXXX")

# Scratch files. printf with \xe2\x80\x9c/\x9d = curly “ ”, \x9d/\x9c = reversed.
printf 'message1 = "hello"\nmessage2 = \xe2\x80\x9chello\xe2\x80\x9d\n'        > "$D/mixed.py"
printf 'message1 = \xe2\x80\x9dhello\xe2\x80\x9c\nmessage2 = \xe2\x80\x9chello\xe2\x80\x9d\n' > "$D/subtle.py"
printf 'only = \xe2\x80\x9cgreeting\xe2\x80\x9d\n'                              > "$D/curly_only.py"
printf 'a = "x"\nb = "y"\n'                                                    > "$D/plain.py"
printf 'dup = "z"\ndup = "z"\n'                                                > "$D/rawdup.py"

# Run hook with a JSON payload; print "exit|stderr_line_count".
run_in() {
  local payload="$1" err rc
  err=$(printf '%s' "$payload" | bash "$HOOK" 2>&1 1>/dev/null); rc=$?
  echo "$rc|$(printf '%s' "$err" | grep -c .)"
}

echo "Testing edit-quote-ambiguity-guard.sh"
echo "====================================="

# 1. Subtle variant (raw 0, norm 2) → BLOCK (exit 2 with message).
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/subtle.py\",\"old_string\":\"\\\"hello\\\"\",\"new_string\":\"X\"}}")
[ "${R%%|*}" = "2" ] && [ "${R##*|}" -gt 0 ] && run_test "subtle two-curly variant → blocks" pass || run_test "subtle → blocks ($R)" fail

# 2. Mixed straight+curly (raw 1, norm 2) → BLOCK.
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/mixed.py\",\"old_string\":\"\\\"hello\\\"\",\"new_string\":\"X\"}}")
[ "${R%%|*}" = "2" ] && run_test "mixed exact-wins ambiguity → blocks" pass || run_test "mixed → blocks ($R)" fail

# 3. Curly-only unique (raw 0, norm 1) → allow (exit 0).
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/curly_only.py\",\"old_string\":\"\\\"greeting\\\"\",\"new_string\":\"X\"}}")
[ "${R%%|*}" = "0" ] && run_test "curly-only unique normalized match → allows" pass || run_test "curly-only → allows ($R)" fail

# 4. Plain unique (raw 1, norm 1) → allow.
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/plain.py\",\"old_string\":\"\\\"x\\\"\",\"new_string\":\"X\"}}")
[ "${R%%|*}" = "0" ] && run_test "plain unique match → allows" pass || run_test "plain → allows ($R)" fail

# 5. Raw duplicate (raw 2, norm 2) → silent: the tool already rejects this.
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/rawdup.py\",\"old_string\":\"\\\"z\\\"\",\"new_string\":\"X\"}}")
[ "${R%%|*}" = "0" ] && run_test "raw duplicate (tool handles) → stays silent" pass || run_test "rawdup → silent ($R)" fail

# 6. replace_all:true → allow (intentional all-variant change).
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/subtle.py\",\"old_string\":\"\\\"hello\\\"\",\"new_string\":\"X\",\"replace_all\":true}}")
[ "${R%%|*}" = "0" ] && run_test "replace_all:true → allows" pass || run_test "replace_all → allows ($R)" fail

# 7. Non-Edit input (no file_path) → allow.
R=$(run_in '{"tool_input":{"command":"ls"}}')
[ "${R%%|*}" = "0" ] && run_test "no file_path → allows" pass || run_test "no file_path → allows ($R)" fail

# 8. MultiEdit whose 2nd edit is the subtle variant → BLOCK.
R=$(run_in "{\"tool_input\":{\"file_path\":\"$D/subtle.py\",\"edits\":[{\"old_string\":\"x\",\"new_string\":\"y\"},{\"old_string\":\"\\\"hello\\\"\",\"new_string\":\"X\"}]}}")
[ "${R%%|*}" = "2" ] && run_test "MultiEdit with ambiguous edit → blocks" pass || run_test "MultiEdit → blocks ($R)" fail

# 9. Malformed JSON → allow (never break the tool on bad input).
R=$(run_in 'not json')
[ "${R%%|*}" = "0" ] && run_test "malformed JSON → allows" pass || run_test "malformed → allows ($R)" fail

rm -rf "$D"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
