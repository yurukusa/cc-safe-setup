#!/bin/bash
# Tests for forbidden-response-phrase-detector.sh
# Run: bash tests/test-forbidden-response-phrase-detector.sh
set -uo pipefail

HOOK="$(dirname "$0")/../examples/forbidden-response-phrase-detector.sh"
PASS=0 FAIL=0

# Helper: build a temp transcript with one assistant response, run the hook with
# an explicit CLAUDE.md path, assert the exit code.
run_test() {
    local desc="$1" expected_exit="$2" response="$3" claudemd_content="$4" envvars="${5:-}"
    local tmpdir transcript claudemd actual_exit input
    tmpdir=$(mktemp -d)
    transcript="${tmpdir}/transcript.jsonl"
    claudemd="${tmpdir}/CLAUDE.md"
    printf '%s' "$claudemd_content" > "$claudemd"

    jq -nc --arg text "$response" '{
        "role": "assistant",
        "message": {"role": "assistant", "content": [{"type": "text", "text": $text}]}
    }' > "$transcript"

    input=$(jq -nc --arg t "$transcript" '{"transcript_path": $t}')

    if [ -n "$envvars" ]; then
        actual_exit=$(echo "$input" | env CC_CLAUDEMD_PATH="$claudemd" $envvars bash "$HOOK" >/dev/null 2>/dev/null; echo $?)
    else
        echo "$input" | CC_CLAUDEMD_PATH="$claudemd" bash "$HOOK" >/dev/null 2>/dev/null
        actual_exit=$?
    fi

    rm -rf "$tmpdir"

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

expect_stderr_contains() {
    local desc="$1" response="$2" claudemd_content="$3" expect="$4" envvars="${5:-}"
    local tmpdir transcript claudemd stderr_out input
    tmpdir=$(mktemp -d)
    transcript="${tmpdir}/transcript.jsonl"
    claudemd="${tmpdir}/CLAUDE.md"
    printf '%s' "$claudemd_content" > "$claudemd"

    jq -nc --arg text "$response" '{
        "role": "assistant",
        "message": {"role": "assistant", "content": [{"type": "text", "text": $text}]}
    }' > "$transcript"

    input=$(jq -nc --arg t "$transcript" '{"transcript_path": $t}')

    if [ -n "$envvars" ]; then
        stderr_out=$(echo "$input" | env CC_CLAUDEMD_PATH="$claudemd" $envvars bash "$HOOK" 2>&1 >/dev/null)
    else
        stderr_out=$(echo "$input" | CC_CLAUDEMD_PATH="$claudemd" bash "$HOOK" 2>&1 >/dev/null)
    fi

    rm -rf "$tmpdir"

    if echo "$stderr_out" | grep -q -- "$expect"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (stderr missing '$expect')"
        echo "       got: $stderr_out"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing forbidden-response-phrase-detector.sh"
echo "============================================="

# --- BASELINE ---
run_test "no CLAUDE.md → exit 0" 0 "Some response" ""
run_test "CLAUDE.md without prohibitions → exit 0" 0 "You're right that the issue is..." "# project notes\nuse anything"

# --- PROSE PROHIBITIONS ---
run_test "Do NOT open with You're right blocks" \
    0 "You're right that the issue is here." \
    "Do NOT open replies with \`You're right\`."

run_test "never say I apologize warns" \
    0 "I apologize for the confusion." \
    "never say \`I apologize\` in responses."

run_test "do not use Great point blocks" \
    0 "Great point about that." \
    "Do not use \`Great point\` as an opener."

# --- BLOCK MODE ---
run_test "BLOCK=1 with violation exits 2" \
    2 "You're right that..." \
    "Do NOT open with \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "BLOCK=1 with clean response exits 0" \
    0 "Looking at the code, I see the issue is..." \
    "Do NOT open with \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

# --- DISABLE ---
run_test "DISABLE=1 short-circuits" \
    0 "You're right" \
    "Do NOT use \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_DISABLE=1"

# --- OPEN_ONLY ---
# Response is 250+ chars; "Great point" appears at char ~210, JUST past the 200-char window
LONG_RESPONSE_OPEN_ONLY="Here is a thorough analysis of the existing implementation that covers all the edge cases we have observed in production over the past several weeks of operation since the deployment of the most recent revision. Great point about backwards compatibility."
run_test "OPEN_ONLY=1 limits scope to first 200 chars (violation outside window)" \
    0 "$LONG_RESPONSE_OPEN_ONLY" \
    "Do NOT say \`Great point\` in opening." \
    "CC_FORBIDDEN_PHRASE_OPEN_ONLY=1 CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "OPEN_ONLY=1 catches violation in first 200 chars" \
    2 "Great point about that. Let me look at the code." \
    "Do NOT say \`Great point\` in opening." \
    "CC_FORBIDDEN_PHRASE_OPEN_ONLY=1 CC_FORBIDDEN_PHRASE_BLOCK=1"

# --- CASE SENSITIVITY ---
run_test "case-insensitive (default) matches mixed-case violation" \
    2 "you're right that we need to fix this." \
    "Do NOT open with \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "CASE_SENSITIVE=1 does not match lowercase" \
    0 "you're right that we need to fix this." \
    "Do NOT open with \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_CASE_SENSITIVE=1 CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "CASE_SENSITIVE=1 matches exact case" \
    2 "You're right that we need to fix this." \
    "Do NOT open with \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_CASE_SENSITIVE=1 CC_FORBIDDEN_PHRASE_BLOCK=1"

# --- HEADER LIST FORMAT ---
run_test "Forbidden Response Phrases header list blocks violation" \
    2 "You're right that this needs work." \
    "## Forbidden Response Phrases

- \`You're right\`
- \`Great point\`
- \`I apologize\`" \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "Filler Phrases header list blocks violation" \
    2 "Great point — let me investigate." \
    "## Filler Phrases

- \`Great point\`
- \`Exactly\`" \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

# --- JAPANESE ---
run_test "Japanese: 了解しました prohibition blocks" \
    2 "了解しました。 修正を行います。" \
    "\`了解しました\` を返信の冒頭で使うな。" \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "Japanese: header 禁止する応答 list blocks" \
    2 "はい、その通りです。" \
    "## 禁止する応答

- \`はい、その通りです\`
- \`了解しました\`" \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

# --- NEGATIVE CASES ---
run_test "Phrase not in response → exit 0" \
    0 "Let me look at the code and analyse the issue." \
    "Do NOT use \`You're right\`."

run_test "Different phrase in prohibition does not match different phrase in response" \
    0 "Great point about that." \
    "Do NOT use \`You're absolutely correct\`."

# --- STDERR ---
expect_stderr_contains \
    "stderr names the violated phrase" \
    "You're right that..." \
    "Do NOT open with \`You're right\`." \
    "You're right"

expect_stderr_contains \
    "stderr cites issue #60339" \
    "You're right" \
    "Do NOT open with \`You're right\`." \
    "#60339"

expect_stderr_contains \
    "stderr says detector header" \
    "You're right" \
    "Do NOT open with \`You're right\`." \
    "forbidden-response-phrase-detector"

# --- COMBINED FORMATS ---
run_test "combined prose + header list works" \
    2 "You're absolutely correct here." \
    "## Forbidden Response Phrases
- \`I apologize\`

Also do NOT say \`You're absolutely correct\`." \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

# --- EDGE CASES ---
run_test "phrase requires backticks; bare mention does not parse" \
    0 "You're right" \
    "Do NOT say You're right (no backticks here)."

run_test "empty response → exit 0" \
    0 "" \
    "Do NOT use \`You're right\`."

run_test "phrase appearing in code block (legitimate code, not natural-language)" \
    2 "Here is some code: \`You're right\` — but this is just text matching." \
    "Do NOT use \`You're right\`." \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

# Note: the hook intentionally does not try to distinguish code blocks from
# narrative text. The operator's CLAUDE.md should be specific enough that
# inadvertent matches are rare. If false positives become an issue, the
# operator can refine the phrase list or use CASE_SENSITIVE mode.

# --- #60339 REPRODUCTION ---
RESPONSE_FROM_60339="You are right that the issue with hook execution is..."
CLAUDEMD_60339="## Response style rules

Do NOT open replies with filler phrases like \`You are right\`, \`Great point\`, or \`I apologize\`."

run_test "#60339 reproduction: forbidden opener blocks" \
    2 "$RESPONSE_FROM_60339" "$CLAUDEMD_60339" \
    "CC_FORBIDDEN_PHRASE_BLOCK=1"

run_test "#60339 reproduction with clean response passes" \
    0 "Looking at the hook configuration, the issue is..." "$CLAUDEMD_60339"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
