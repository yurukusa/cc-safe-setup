#!/bin/bash
# Tests for authorized-reconfirmation-detector.sh
#
# Verifies the Stop-hook behavior for anthropics/claude-code#61929 case (3):
# AskUserQuestion fired on an action that the operator's prior turn
# already authorized. The hook is a measurement layer — it never blocks.

set -uo pipefail

HOOK="$(dirname "$0")/../examples/authorized-reconfirmation-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Use a per-run temp log so tests don't collide.
LOG_TMP=$(mktemp -t auth-reconf-test.XXXXXX)
trap 'rm -f "$LOG_TMP"' EXIT

run_hook() {
    local input="$1"
    : > "$LOG_TMP"
    export CC_AUTH_RECONF_LOG="$LOG_TMP"
    printf '%s' "$input" | bash "$HOOK" 2>&1
}

# Build a minimal transcript JSON with the operator turn + an AUQ tool call.
make_input() {
    local user_msg="$1"
    local question="$2"
    local options_json="$3"  # JSON array of {label, description}
    jq -nc \
        --arg um "$user_msg" \
        --arg q "$question" \
        --argjson opts "$options_json" \
        '{
            transcript: [
                {role: "user",      content: $um},
                {role: "assistant", tool_calls: [
                    {name: "AskUserQuestion",
                     input: {questions: [{question: $q, options: $opts}]}}
                ]}
            ]
        }'
}

echo "=== authorized-reconfirmation-detector.sh tests ==="

# --- Test 1: positive — user said "deploy" + AUQ asks about deploy + Recommended ---
INPUT=$(make_input \
    "deploy the staging build" \
    "Should I deploy to staging?" \
    '[{"label":"Yes (Recommended)","description":"proceed with deploy"},
      {"label":"No","description":"hold off"}]')
run_hook "$INPUT" >/dev/null
if [ -s "$LOG_TMP" ] \
   && grep -q '"event":"authorized_reconfirmation_detected"' "$LOG_TMP" \
   && grep -q '"matched_word":"deploy"' "$LOG_TMP"; then
    assert_pass "positive: AUQ with Recommended + verb echo logs detection"
else
    cat "$LOG_TMP" >&2
    assert_fail "positive case did not produce expected log entry"
fi

# --- Test 2: negative — genuine fork (no Recommended marker) ---
INPUT=$(make_input \
    "set up the project, please" \
    "Which database should we use?" \
    '[{"label":"Postgres","description":"relational"},
      {"label":"MongoDB","description":"document"}]')
run_hook "$INPUT" >/dev/null
if [ ! -s "$LOG_TMP" ]; then
    assert_pass "negative: genuine fork (no Recommended) produces no log"
else
    cat "$LOG_TMP" >&2
    assert_fail "genuine-fork case incorrectly logged"
fi

# --- Test 3: negative — Recommended marker but no verb echo from user ---
INPUT=$(make_input \
    "hi, how are you" \
    "Should I deploy to staging?" \
    '[{"label":"Yes (Recommended)","description":"proceed with deploy"}]')
run_hook "$INPUT" >/dev/null
if [ ! -s "$LOG_TMP" ]; then
    assert_pass "negative: no verb echo in user message produces no log"
else
    cat "$LOG_TMP" >&2
    assert_fail "no-echo case incorrectly logged"
fi

# --- Test 4: positive — Japanese "推奨" marker matches ---
INPUT=$(make_input \
    "migrate the table to the new schema" \
    "Should I migrate the schema now?" \
    '[{"label":"はい","description":"続行 推奨"},
      {"label":"いいえ","description":"中止"}]')
run_hook "$INPUT" >/dev/null
if grep -q '"matched_word":"migrate"\|"matched_word":"schema"' "$LOG_TMP"; then
    assert_pass "positive: Japanese 推奨 marker triggers detection"
else
    cat "$LOG_TMP" >&2
    assert_fail "Japanese marker case did not log"
fi

# --- Test 5: positive — multi-word verb stem echo ---
INPUT=$(make_input \
    "go ahead and rebuild the docker image" \
    "Should I rebuild the container image?" \
    '[{"label":"(Recommended) Yes","description":"rebuild now"}]')
run_hook "$INPUT" >/dev/null
if grep -q '"matched_word":"rebuild"\|"matched_word":"image"' "$LOG_TMP"; then
    assert_pass "positive: multi-word verb stem echo logs detection"
else
    cat "$LOG_TMP" >&2
    assert_fail "multi-word echo did not log"
fi

# --- Test 6: hook never blocks (exit 0 even on detection) ---
INPUT=$(make_input \
    "run the test suite" \
    "Should I run the tests now?" \
    '[{"label":"(Recommended) yes","description":"run them"}]')
output=$(run_hook "$INPUT")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "hook exits 0 with no stdout/stderr on detection (measurement only)"
else
    assert_fail "expected silent exit 0 on detection, got rc=$rc output=$output"
fi

# --- Test 7: empty input is a silent no-op ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input is a silent no-op"
else
    assert_fail "empty input should be silent (rc=$rc output=$output)"
fi

# --- Test 8: malformed JSON is a silent no-op (no false positive) ---
output=$(printf 'not json at all' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "malformed input is silent (no false positive)"
else
    assert_fail "malformed input should be silent (rc=$rc output=$output)"
fi

# --- Test 9: no AUQ tool call → silent no-op ---
INPUT=$(jq -nc '{transcript: [
    {role: "user", content: "do the thing"},
    {role: "assistant", tool_calls: [{name: "Bash", input: {command: "ls"}}]}
]}')
run_hook "$INPUT" >/dev/null
if [ ! -s "$LOG_TMP" ]; then
    assert_pass "no AUQ tool call → no log"
else
    assert_fail "non-AUQ turn incorrectly logged"
fi

# --- Test 10: CC_AUTH_RECONF_DISABLE=1 respected ---
INPUT=$(make_input \
    "deploy the staging build" \
    "Should I deploy?" \
    '[{"label":"(Recommended) yes","description":"deploy"}]')
: > "$LOG_TMP"
export CC_AUTH_RECONF_LOG="$LOG_TMP" CC_AUTH_RECONF_DISABLE=1
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
unset CC_AUTH_RECONF_DISABLE
if [ ! -s "$LOG_TMP" ]; then
    assert_pass "CC_AUTH_RECONF_DISABLE=1 suppresses all logging"
else
    assert_fail "disable flag was ignored"
fi

# --- Test 11: stopword-only AUQ question does not match common stopwords ---
INPUT=$(make_input \
    "this would be nice" \
    "Should I proceed with this?" \
    '[{"label":"(Recommended) yes","description":"go"}]')
run_hook "$INPUT" >/dev/null
if [ ! -s "$LOG_TMP" ]; then
    assert_pass "stopword-only echo (e.g. 'this', 'should') does not match"
else
    cat "$LOG_TMP" >&2
    assert_fail "stopwords incorrectly produced a match"
fi

# --- Test 12: log entry shape includes timestamp, event, question, word, excerpt ---
INPUT=$(make_input \
    "deploy the build" \
    "Should I deploy?" \
    '[{"label":"(Recommended) yes","description":"deploy"}]')
run_hook "$INPUT" >/dev/null
ENTRY=$(head -1 "$LOG_TMP")
if echo "$ENTRY" | jq -e '
    has("timestamp") and has("event") and has("auq_question")
    and has("matched_word") and has("user_excerpt")
' >/dev/null 2>&1; then
    assert_pass "log entry has all required fields"
else
    echo "  entry: $ENTRY"
    assert_fail "log entry missing fields"
fi

# --- Test 13: alternate transcript shape (content array of message parts) ---
INPUT=$(jq -nc '{transcript: [
    {role: "user", content: [{type: "text", text: "deploy the staging build"}]},
    {role: "assistant", tool_calls: [
        {name: "AskUserQuestion",
         input: {questions: [
            {question: "Should I deploy to staging?",
             options: [{label: "(Recommended) Yes", description: "proceed"}]}
         ]}}
    ]}
]}')
run_hook "$INPUT" >/dev/null
if grep -q '"matched_word":"deploy"' "$LOG_TMP"; then
    assert_pass "handles content-array user messages"
else
    cat "$LOG_TMP" >&2
    assert_fail "content-array user shape did not log"
fi

# --- Test 14: AUQ without options array → no false positive ---
INPUT=$(jq -nc '{transcript: [
    {role: "user", content: "deploy the build"},
    {role: "assistant", tool_calls: [
        {name: "AskUserQuestion",
         input: {questions: [{question: "Should I deploy?"}]}}
    ]}
]}')
run_hook "$INPUT" >/dev/null
if [ ! -s "$LOG_TMP" ]; then
    assert_pass "AUQ without options is silent (no Recommended marker possible)"
else
    cat "$LOG_TMP" >&2
    assert_fail "AUQ without options incorrectly logged"
fi

# --- Test 15: case-insensitive "Recommended" marker ---
INPUT=$(make_input \
    "rebuild the container" \
    "Should I rebuild the container?" \
    '[{"label":"yes (RECOMMENDED)","description":"go"}]')
run_hook "$INPUT" >/dev/null
if grep -q '"event":"authorized_reconfirmation_detected"' "$LOG_TMP"; then
    assert_pass "case-insensitive (RECOMMENDED) marker matches"
else
    cat "$LOG_TMP" >&2
    assert_fail "uppercase RECOMMENDED did not match"
fi

# --- Test 16: multiple AUQ questions in one call → all evaluated ---
INPUT=$(jq -nc '{transcript: [
    {role: "user", content: "deploy and restart the service"},
    {role: "assistant", tool_calls: [
        {name: "AskUserQuestion",
         input: {questions: [
            {question: "Should I deploy first?",
             options: [{label: "(Recommended) yes", description: "go"}]},
            {question: "Should I restart afterwards?",
             options: [{label: "(Recommended) yes", description: "go"}]}
         ]}}
    ]}
]}')
run_hook "$INPUT" >/dev/null
N=$(grep -c '"event":"authorized_reconfirmation_detected"' "$LOG_TMP" || true)
if [ "${N:-0}" -ge 2 ]; then
    assert_pass "multiple questions in one AUQ call all evaluated"
else
    cat "$LOG_TMP" >&2
    assert_fail "expected >=2 log entries, got ${N:-0}"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
