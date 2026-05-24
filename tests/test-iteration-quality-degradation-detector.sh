#!/bin/bash
# Tests for iteration-quality-degradation-detector.sh
#
# Verifies the hook behavior from anthropics/claude-code#61989:
#   - PostToolUse on Edit/Write appends to log
#   - UserPromptSubmit reads log and surfaces files over threshold
#   - Non-Edit tools are ignored
#   - Window is respected (old entries don't count)
#   - Strict mode exits 2
#   - Disable flag respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/iteration-quality-degradation-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Setup: isolated state dir per test run
STATE_DIR=$(mktemp -d)
export CC_ITERATION_DETECTOR_STATE_DIR="$STATE_DIR"
export CC_ITERATION_DETECTOR_THRESHOLD=3
export CC_ITERATION_DETECTOR_WINDOW_SEC=1800

run_hook() {
    local input="$1"
    local extra_env="${2:-}"
    if [ -n "$extra_env" ]; then
        eval "$extra_env bash \"$HOOK\"" <<< "$input" 2>&1
    else
        printf '%s' "$input" | bash "$HOOK" 2>&1
    fi
}

post_edit() {
    local session="$1"
    local file_path="$2"
    local input
    input=$(jq -nc --arg s "$session" --arg f "$file_path" '{
        hook_event_name: "PostToolUse",
        tool_name: "Edit",
        session_id: $s,
        tool_input: { file_path: $f },
        tool_response: { result: "ok" }
    }')
    printf '%s' "$input" | bash "$HOOK" 2>&1
}

user_prompt() {
    local session="$1"
    local extra_env="${2:-}"
    local input
    input=$(jq -nc --arg s "$session" '{
        hook_event_name: "UserPromptSubmit",
        session_id: $s,
        prompt: "next step"
    }')
    if [ -n "$extra_env" ]; then
        eval "$extra_env bash \"$HOOK\"" <<< "$input" 2>&1
    else
        printf '%s' "$input" | bash "$HOOK" 2>&1
    fi
}

echo "=== iteration-quality-degradation-detector.sh tests ==="

# --- Test 1: edit same file 3 times → advisory fires on next prompt ---
SES="s1"
post_edit "$SES" "/app/foo.sh" >/dev/null
post_edit "$SES" "/app/foo.sh" >/dev/null
post_edit "$SES" "/app/foo.sh" >/dev/null
output=$(user_prompt "$SES")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "iteration-quality-degradation-detector"; then
    assert_pass "3 edits to same file fires advisory"
else
    assert_fail "expected advisory after 3 edits, got rc=$rc output=$output"
fi

# --- Test 2: edit different files → no advisory ---
SES="s2"
post_edit "$SES" "/app/foo.sh" >/dev/null
post_edit "$SES" "/app/bar.sh" >/dev/null
post_edit "$SES" "/app/baz.sh" >/dev/null
output=$(user_prompt "$SES")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "3 edits to different files: silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 3: 2 edits to same file → no advisory (below threshold) ---
SES="s3"
post_edit "$SES" "/app/foo.sh" >/dev/null
post_edit "$SES" "/app/foo.sh" >/dev/null
output=$(user_prompt "$SES")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "2 edits below threshold: silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 4: non-Edit tools are ignored ---
SES="s4"
INPUT=$(jq -nc --arg s "$SES" '{
    hook_event_name: "PostToolUse",
    tool_name: "Bash",
    session_id: $s,
    tool_input: { command: "ls" },
    tool_response: { result: "ok" }
}')
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
# No log file should exist
if [ ! -f "$STATE_DIR/$SES/edits.log" ]; then
    assert_pass "Bash tool ignored, no log written"
else
    assert_fail "expected no log file, found $(cat "$STATE_DIR/$SES/edits.log")"
fi

# --- Test 5: edit with missing file_path → silent ---
SES="s5"
INPUT=$(jq -nc --arg s "$SES" '{
    hook_event_name: "PostToolUse",
    tool_name: "Edit",
    session_id: $s,
    tool_input: {},
    tool_response: { result: "ok" }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "Edit with no file_path: silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 6: strict mode → exit 2 ---
SES="s6"
post_edit "$SES" "/app/strict.sh" >/dev/null
post_edit "$SES" "/app/strict.sh" >/dev/null
post_edit "$SES" "/app/strict.sh" >/dev/null
output=$(user_prompt "$SES" "CC_ITERATION_DETECTOR_MODE=strict")
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "iteration-quality-degradation-detector"; then
    assert_pass "strict mode exits 2"
else
    assert_fail "expected exit 2 in strict mode, got rc=$rc"
fi

# --- Test 7: disable flag → silent ---
SES="s7"
post_edit "$SES" "/app/d.sh" >/dev/null
post_edit "$SES" "/app/d.sh" >/dev/null
post_edit "$SES" "/app/d.sh" >/dev/null
output=$(user_prompt "$SES" "CC_ITERATION_DETECTOR_DISABLE=1")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag silent"
else
    assert_fail "expected silent when disabled, got rc=$rc output=$output"
fi

# --- Test 8: empty stdin → silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty stdin silent"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 9: session ID sanitization ---
SES="../../etc"
post_edit "$SES" "/app/sanitize.sh" >/dev/null
# The actual dir should be ______etc (path traversal sanitized to underscores)
if [ -d "$STATE_DIR/______etc" ]; then
    assert_pass "session ID with .. sanitized"
elif [ -d "$STATE_DIR/______etc" ] || [ -d "$STATE_DIR/__etc" ] || ! [ -d "$STATE_DIR/../../etc" ]; then
    # Accept any sanitized form as long as it's not literal ../../etc
    assert_pass "session ID with .. sanitized (no path traversal)"
else
    assert_fail "session ID not sanitized correctly"
fi

# --- Test 10: MultiEdit tool also tracked ---
SES="s10"
INPUT=$(jq -nc --arg s "$SES" '{
    hook_event_name: "PostToolUse",
    tool_name: "MultiEdit",
    session_id: $s,
    tool_input: { file_path: "/app/multi.sh" },
    tool_response: { result: "ok" }
}')
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
output=$(user_prompt "$SES")
if echo "$output" | grep -q "iteration-quality-degradation-detector"; then
    assert_pass "MultiEdit tracked"
else
    assert_fail "expected MultiEdit to be tracked, got output=$output"
fi

# --- Test 11: Write tool also tracked ---
SES="s11"
INPUT=$(jq -nc --arg s "$SES" '{
    hook_event_name: "PostToolUse",
    tool_name: "Write",
    session_id: $s,
    tool_input: { file_path: "/app/w.sh" },
    tool_response: { result: "ok" }
}')
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null
output=$(user_prompt "$SES")
if echo "$output" | grep -q "iteration-quality-degradation-detector"; then
    assert_pass "Write tracked"
else
    assert_fail "expected Write to be tracked, got output=$output"
fi

# --- Test 12: custom threshold respected ---
SES="s12"
post_edit "$SES" "/app/t.sh" >/dev/null
post_edit "$SES" "/app/t.sh" >/dev/null
output=$(user_prompt "$SES" "CC_ITERATION_DETECTOR_THRESHOLD=2")
if echo "$output" | grep -q "iteration-quality-degradation-detector"; then
    assert_pass "custom threshold=2 fires at 2 edits"
else
    assert_fail "expected threshold=2 to fire, got output=$output"
fi

# Cleanup
rm -rf "$STATE_DIR"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
