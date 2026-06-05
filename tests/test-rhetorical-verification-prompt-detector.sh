#!/bin/bash
# Tests for rhetorical-verification-prompt-detector.sh
# Run: bash tests/test-rhetorical-verification-prompt-detector.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/rhetorical-verification-prompt-detector.sh"

run_hook() {
    local prompt="$1"
    local extra_env="${2:-}"
    if [ -n "$extra_env" ]; then
        printf '{"prompt":%s}' "$(jq -Rs . <<< "$prompt")" | env -i PATH="$PATH" $extra_env bash "$HOOK" 2>&1
    else
        printf '{"prompt":%s}' "$(jq -Rs . <<< "$prompt")" | env -i PATH="$PATH" bash "$HOOK" 2>&1
    fi
}

assert_silent() {
    local label="$1"
    local output="$2"
    if [ -z "$output" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $label"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label"
        echo "    expected silent, got: ${output:0:200}"
    fi
}

assert_emits_context() {
    local label="$1"
    local output="$2"
    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        local ctx
        ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
        if echo "$ctx" | grep -q "Verification-intent detected"; then
            PASS=$((PASS + 1))
            echo "  ✓ $label"
        else
            FAIL=$((FAIL + 1))
            echo "  ✗ $label (context missing marker)"
            echo "    got context: ${ctx:0:200}"
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label (no hookSpecificOutput)"
        echo "    got: ${output:0:200}"
    fi
}

assert_emits_with_marker() {
    local label="$1"
    local output="$2"
    local expected_marker_substring="$3"
    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        local ctx
        ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
        if echo "$ctx" | grep -qi "$expected_marker_substring"; then
            PASS=$((PASS + 1))
            echo "  ✓ $label"
        else
            FAIL=$((FAIL + 1))
            echo "  ✗ $label (marker not found in context)"
            echo "    expected marker: $expected_marker_substring"
            echo "    got context: ${ctx:0:300}"
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label (no output)"
    fi
}

echo "=== Silent cases (no verification intent) ==="

OUT=$(run_hook "Please write a Python script that calculates fibonacci numbers.")
assert_silent "task prompt — no verification intent" "$OUT"

OUT=$(run_hook "Add a new function to handle error cases.")
assert_silent "task prompt — modification request" "$OUT"

OUT=$(run_hook "What is the time complexity of quicksort?")
assert_silent "knowledge question — not verification" "$OUT"

OUT=$(run_hook "Show me the contents of README.md")
assert_silent "read request — not verification" "$OUT"

OUT=$(run_hook "Explain how OAuth2 works.")
assert_silent "explanation request — not verification" "$OUT"

OUT=$(run_hook "")
assert_silent "empty prompt" "$OUT"

# JSON without prompt key
OUT=$(echo '{}' | env -i PATH="$PATH" bash "$HOOK" 2>&1)
assert_silent "no prompt key in input" "$OUT"

echo ""
echo "=== English verification intent — should emit context ==="

OUT=$(run_hook "Are you sure this is the right approach?")
assert_emits_context "are you sure" "$OUT"

OUT=$(run_hook "Did this actually work in production?")
assert_emits_context "did this actually" "$OUT"

OUT=$(run_hook "Can you confirm that the database is properly migrated?")
assert_emits_context "can you confirm" "$OUT"

OUT=$(run_hook "Is this really safe to deploy?")
assert_emits_context "is this really safe" "$OUT"

OUT=$(run_hook "Did you verify the changes are committed?")
assert_emits_context "did you verify" "$OUT"

OUT=$(run_hook "Please double-check the configuration before we proceed.")
assert_emits_context "please double-check" "$OUT"

OUT=$(run_hook "Just to be sure — did the deployment complete?")
assert_emits_context "just to be sure" "$OUT"

OUT=$(run_hook "Are you certain this is correct?")
assert_emits_context "are you certain" "$OUT"

OUT=$(run_hook "Is this actually working correctly?")
assert_emits_context "is this actually working" "$OUT"

OUT=$(run_hook "Sanity check: did all the tests pass?")
assert_emits_context "sanity check" "$OUT"

echo ""
echo "=== Japanese verification intent — should emit context ==="

OUT=$(run_hook "本当に動いてる?")
assert_emits_context "本当に動いてる?" "$OUT"

OUT=$(run_hook "確認したかどうかチェックして")
assert_emits_context "確認した" "$OUT"

OUT=$(run_hook "もう一度確認してください")
assert_emits_context "もう一度確認" "$OUT"

OUT=$(run_hook "本当に成功したのか?")
assert_emits_context "本当に成功した" "$OUT"

OUT=$(run_hook "間違いないですか?")
assert_emits_context "間違いないですか" "$OUT"

OUT=$(run_hook "大丈夫?")
assert_emits_context "大丈夫?" "$OUT"

echo ""
echo "=== Marker propagation ==="

OUT=$(run_hook "Are you sure the migration ran cleanly?")
assert_emits_with_marker "marker 'are you sure' appears in context" "$OUT" "are you sure"

OUT=$(run_hook "本当に保存されたか?")
assert_emits_with_marker "marker '本当に' appears in context" "$OUT" "本当に"

echo ""
echo "=== Configuration ==="

OUT=$(run_hook "Are you sure?" "CC_RHETORICAL_VERIFY_DISABLE=1")
assert_silent "CC_RHETORICAL_VERIFY_DISABLE=1 silences output" "$OUT"

# Logging
LOG_FILE=$(mktemp)
trap 'rm -f "$LOG_FILE"' EXIT
OUT=$(run_hook "Did this really deploy?" "CC_RHETORICAL_VERIFY_LOG=$LOG_FILE")
assert_emits_context "logging enabled still emits context" "$OUT"
if grep -q "rhetorical-verify-detected" "$LOG_FILE" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ log file contains detection event"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ log file missing detection event"
fi

echo ""
echo "=== JSON structure ==="

OUT=$(run_hook "Are you sure this is right?")
# Check it's valid JSON
if echo "$OUT" | jq -e '.' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  ✓ output is valid JSON"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ output is not valid JSON: ${OUT:0:200}"
fi

HOOK_NAME=$(echo "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
if [ "$HOOK_NAME" = "UserPromptSubmit" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ hookEventName is UserPromptSubmit"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ hookEventName missing or wrong: $HOOK_NAME"
fi

# Check Issue reference appears in context
CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty')
if echo "$CTX" | grep -q "60107"; then
    PASS=$((PASS + 1))
    echo "  ✓ context references Issue #60107"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ context missing Issue #60107 reference"
fi

echo ""
echo "=== Edge cases ==="

# Verification intent inside a larger task should still trigger
OUT=$(run_hook "Refactor the auth module. Are you sure the tests still pass after?")
assert_emits_context "verification intent in mixed-purpose prompt" "$OUT"

# Affirmative-sounding but not verification ("I'm sure")
OUT=$(run_hook "I'm sure this is the right approach. Let's continue.")
assert_silent "affirmative declaration (not verification)" "$OUT"

# Long prompt with verification intent at the end
OUT=$(run_hook "I implemented the migration script following our usual pattern, ran it against the staging database, and got the expected output. The script created the new columns, copied the data, and validated the row counts. Are you certain this is ready for production?")
assert_emits_context "verification intent at end of long prompt" "$OUT"

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))   PASS: $PASS   FAIL: $FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
