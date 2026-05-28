#!/bin/bash
# Tests for xml-format-leak-detector.sh
HOOK="examples/xml-format-leak-detector.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
STATE_DIR="$TMPDIR/state"
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

reset_state() { rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"; }

mk_input() {
    local transcript="$1" sid="${2:-test-session}"
    printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript" "$sid"
}

# A clean tool_use block: JSON arguments only, no XML leak.
mk_clean_tool_use() {
    printf '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"log_outcome","input":{"summary":"all done","files":["a.txt","b.txt"]}}]}}\n'
}

# A 12D-shape tool_use: the summary string ends with </summary> and
# subsequent parameters appear as <parameter name="files_modified">
# inside the JSON string. This is the literal #49747 example.
mk_leaked_tool_use() {
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"log_outcome","input":{"summary":"did things.</summary>\n<parameter name=\"files_modified\">[\"a.txt\"]</parameter>","status":"completed"}}]}}'
}

# A 12D-shape with </invoke> marker.
mk_leaked_invoke() {
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"some_tool","input":{"arg":"text</invoke>"}}]}}'
}

# A 12D-shape with </function_calls> marker.
mk_leaked_function_calls() {
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"x","input":{"arg":"value</function_calls>"}}]}}'
}

# A 12D-shape with <invoke name= marker.
mk_leaked_invoke_open() {
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"t4","name":"y","input":{"arg":"prefix <invoke name=\"z\">suffix"}}]}}'
}

# A top-level (non-.message) tool_use with leak.
mk_leaked_top_level() {
    printf '%s\n' '{"role":"assistant","content":[{"type":"tool_use","id":"t5","name":"q","input":{"arg":"<parameter name=\"x\">y</parameter>"}}]}'
}

# A user-turn line carrying XML markers in tool_result content —
# this is documentation/discussion, not a 12D leak. Must NOT count.
mk_user_text_with_xml() {
    printf '%s\n' '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"the <parameter name=\"foo\"> tag was emitted"}]}}'
}

# An assistant text block (not tool_use) mentioning XML markers —
# also discussion, not a 12D leak. Must NOT count.
mk_assistant_text_with_xml() {
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"models sometimes leak </parameter> into output"}]}}'
}

# Test 1: No transcript path → silent pass
reset_state
OUT=$(echo '{}' | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no transcript silent" "$OUT" "sub-pattern 12D"
assert_exit "no transcript exit 0" "$RC" "0"

# Test 2: Missing transcript file → silent pass
reset_state
OUT=$(mk_input "/nonexistent/transcript.jsonl" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "missing transcript silent" "$OUT" "sub-pattern 12D"
assert_exit "missing transcript exit 0" "$RC" "0"

# Test 3: Clean tool_use blocks only → silent pass
reset_state
TR="$TMPDIR/t3.jsonl"
mk_clean_tool_use > "$TR"
mk_clean_tool_use >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "clean tool_use silent" "$OUT" "sub-pattern 12D"
assert_exit "clean tool_use exit 0" "$RC" "0"

# Test 4: One leaked tool_use → advisory fires
reset_state
TR="$TMPDIR/t4.jsonl"
mk_clean_tool_use > "$TR"
mk_leaked_tool_use >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "one leak fires advisory" "$OUT" "sub-pattern 12D"
assert_contains "advisory cites #49747" "$OUT" "#49747"
assert_contains "advisory cites #62123" "$OUT" "#62123"
assert_contains "advisory mentions XML markers" "$OUT" "XML"
assert_contains "advisory mentions shorten" "$OUT" "Shorten"
assert_contains "advisory mentions cluster tracker" "$OUT" "cluster-tracker"
assert_exit "one leak exit 0" "$RC" "0"

# Test 5: </invoke> marker detected
reset_state
TR="$TMPDIR/t5.jsonl"
mk_leaked_invoke > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "</invoke> detected" "$OUT" "sub-pattern 12D"
assert_exit "</invoke> exit 0" "$RC" "0"

# Test 6: </function_calls> marker detected
reset_state
TR="$TMPDIR/t6.jsonl"
mk_leaked_function_calls > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "</function_calls> detected" "$OUT" "sub-pattern 12D"
assert_exit "</function_calls> exit 0" "$RC" "0"

# Test 7: <invoke name= marker detected
reset_state
TR="$TMPDIR/t7.jsonl"
mk_leaked_invoke_open > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "<invoke name= detected" "$OUT" "sub-pattern 12D"
assert_exit "<invoke name= exit 0" "$RC" "0"

# Test 8: Top-level (non-.message) tool_use detected
reset_state
TR="$TMPDIR/t8.jsonl"
mk_leaked_top_level > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "top-level tool_use detected" "$OUT" "sub-pattern 12D"
assert_exit "top-level exit 0" "$RC" "0"

# Test 9: XML markers in user/tool_result content do NOT count
reset_state
TR="$TMPDIR/t9.jsonl"
mk_user_text_with_xml > "$TR"
mk_user_text_with_xml >> "$TR"
mk_user_text_with_xml >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "XML in tool_result not counted" "$OUT" "sub-pattern 12D"
assert_exit "XML in tool_result exit 0" "$RC" "0"

# Test 10: XML markers in assistant text (not tool_use) do NOT count
reset_state
TR="$TMPDIR/t10.jsonl"
mk_assistant_text_with_xml > "$TR"
mk_assistant_text_with_xml >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "XML in assistant text not counted" "$OUT" "sub-pattern 12D"
assert_exit "XML in assistant text exit 0" "$RC" "0"

# Test 11: Disabled via env → silent even with leaks
reset_state
TR="$TMPDIR/t11.jsonl"
mk_leaked_tool_use > "$TR"
mk_leaked_tool_use >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_DISABLE=1 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable env silences" "$OUT" "sub-pattern 12D"
assert_exit "disable env exit 0" "$RC" "0"

# Test 12: Threshold raised → one leak below threshold silent
reset_state
TR="$TMPDIR/t12.jsonl"
mk_leaked_tool_use > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_THRESHOLD=2 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "threshold 2 with 1 leak silent" "$OUT" "sub-pattern 12D"
assert_exit "threshold 2 with 1 exit 0" "$RC" "0"

# Test 13: Threshold raised, met → advisory fires
reset_state
TR="$TMPDIR/t13.jsonl"
mk_leaked_tool_use > "$TR"
mk_leaked_tool_use >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_THRESHOLD=2 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "threshold 2 with 2 fires" "$OUT" "sub-pattern 12D"
assert_exit "threshold 2 with 2 exit 0" "$RC" "0"

# Test 14: Multiple leaks → advisory shows count
reset_state
TR="$TMPDIR/t14.jsonl"
mk_leaked_tool_use > "$TR"
mk_leaked_invoke >> "$TR"
mk_leaked_function_calls >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "3 leaks fire advisory" "$OUT" "sub-pattern 12D"
assert_contains "advisory shows leak count" "$OUT" "3 tool_use"
assert_exit "3 leaks exit 0" "$RC" "0"

# Test 15: Cooldown — second call within cooldown stays silent
reset_state
TR="$TMPDIR/t15.jsonl"
mk_leaked_tool_use > "$TR"
OUT1=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
OUT2=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "first call fires" "$OUT1" "sub-pattern 12D"
assert_not_contains "second call within cooldown silent" "$OUT2" "sub-pattern 12D"

# Test 16: Cooldown — past cooldown refires
reset_state
TR="$TMPDIR/t16.jsonl"
mk_leaked_tool_use > "$TR"
OUT1=$(mk_input "$TR" | CC_XML_LEAK_COOLDOWN=2 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
# Two no-op calls advance the counter (high threshold suppresses fire)
mk_input "$TR" | CC_XML_LEAK_COOLDOWN=2 CC_XML_LEAK_THRESHOLD=999 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>/dev/null
mk_input "$TR" | CC_XML_LEAK_COOLDOWN=2 CC_XML_LEAK_THRESHOLD=999 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>/dev/null
OUT2=$(mk_input "$TR" | CC_XML_LEAK_COOLDOWN=2 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "first call fires" "$OUT1" "sub-pattern 12D"
assert_contains "third call past cooldown refires" "$OUT2" "sub-pattern 12D"

# Test 17: Different sessions have independent state
reset_state
TR="$TMPDIR/t17.jsonl"
mk_leaked_tool_use > "$TR"
OUT_A=$(mk_input "$TR" "session-A" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
OUT_B=$(mk_input "$TR" "session-B" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "session A fires" "$OUT_A" "sub-pattern 12D"
assert_contains "session B fires independently" "$OUT_B" "sub-pattern 12D"

# Test 18: Lookback window excludes earlier leaks
reset_state
TR="$TMPDIR/t18.jsonl"
mk_leaked_tool_use > "$TR"
for i in $(seq 1 50); do
    mk_clean_tool_use >> "$TR"
done
OUT=$(mk_input "$TR" | CC_XML_LEAK_LOOKBACK=10 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "lookback excludes old leaks" "$OUT" "sub-pattern 12D"
assert_exit "lookback exclude exit 0" "$RC" "0"

# Test 19: Lookback window includes recent leaks
reset_state
TR="$TMPDIR/t19.jsonl"
for i in $(seq 1 5); do
    mk_clean_tool_use >> "$TR"
done
mk_leaked_tool_use >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_LOOKBACK=5 CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "lookback includes recent" "$OUT" "sub-pattern 12D"
assert_exit "lookback include exit 0" "$RC" "0"

# Test 20: Non-JSON lines tolerated; leak still detected
reset_state
TR="$TMPDIR/t20.jsonl"
echo "garbage line not json" > "$TR"
mk_leaked_tool_use >> "$TR"
echo "more garbage" >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "non-json lines tolerated" "$OUT" "sub-pattern 12D"
assert_exit "non-json tolerated exit 0" "$RC" "0"

# Test 21: Mixed clean and leaked — only leaks counted
reset_state
TR="$TMPDIR/t21.jsonl"
mk_clean_tool_use > "$TR"
mk_clean_tool_use >> "$TR"
mk_leaked_tool_use >> "$TR"
mk_clean_tool_use >> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "mixed fires (1 leak)" "$OUT" "sub-pattern 12D"
assert_contains "advisory shows 1 leak" "$OUT" "1 tool_use"
assert_exit "mixed exit 0" "$RC" "0"

# Test 22: Advisory differentiates from 12A / 12B / 12C
reset_state
TR="$TMPDIR/t22.jsonl"
mk_leaked_tool_use > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "advisory mentions 12A distinction" "$OUT" "12A"
assert_contains "advisory mentions 12B distinction" "$OUT" "12B"
assert_contains "advisory mentions 12C distinction" "$OUT" "12C"

# Test 23: Advisory mentions MCP and break-into-smaller workarounds
reset_state
TR="$TMPDIR/t23.jsonl"
mk_leaked_tool_use > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1)
assert_contains "advisory mentions MCP workaround" "$OUT" "MCP"
assert_contains "advisory mentions break into smaller" "$OUT" "smaller"

# Test 24: tool_use without input field is ignored (defensive)
reset_state
TR="$TMPDIR/t24.jsonl"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"x"}]}}' > "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "tool_use without input silent" "$OUT" "sub-pattern 12D"
assert_exit "tool_use without input exit 0" "$RC" "0"

# Test 25: Empty transcript file → silent pass
reset_state
TR="$TMPDIR/t25.jsonl"
> "$TR"
OUT=$(mk_input "$TR" | CC_XML_LEAK_STATE_DIR="$STATE_DIR" bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "empty transcript silent" "$OUT" "sub-pattern 12D"
assert_exit "empty transcript exit 0" "$RC" "0"

echo ""
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
