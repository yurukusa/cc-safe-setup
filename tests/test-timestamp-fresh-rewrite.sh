#!/bin/bash
# Tests for timestamp-fresh-rewrite.sh
#
# Verifies the PreToolUse hook behavior for the #60492 timestamp fabrication
# failure mode:
#   - YYYYMMDDHHMM in file_path that drifts > N minutes from now → substituted
#   - YYYYMMDDHHMM in content that drifts > N minutes from now → substituted
#   - YYYYMMDDHHMM within tolerance band → not substituted (silent exit)
#   - No YYYYMMDDHHMM at all → silent exit
#   - Advisory mode → emits stderr feedback, does not substitute
#   - Disable flag → silent exit, no output
#   - Empty input → silent exit
#   - Different tool names (Write/Edit/MultiEdit) all handled

set -uo pipefail

HOOK="$(dirname "$0")/../examples/timestamp-fresh-rewrite.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

NOW_FULL=$(date +%Y%m%d%H%M)
PAST_VALUE="202504121200"  # April 12, 2026 12:00 — far enough back to trigger

echo "=== timestamp-fresh-rewrite.sh tests ==="

# --- Test 1: drifted timestamp in file_path → substituted ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/archive-" + $val + ".md"),
        content: "hello"
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$output" | jq -e '.decision == "modify"' >/dev/null 2>&1; then
    new_path=$(echo "$output" | jq -r '.tool_input_override.file_path')
    if echo "$new_path" | grep -q "$NOW_FULL"; then
        assert_pass "drifted timestamp in file_path substituted with $NOW_FULL"
    else
        assert_fail "substitution did not include current time, got $new_path"
    fi
else
    assert_fail "expected modify decision, got $output"
fi

# --- Test 2: drifted timestamp in content → substituted ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: "/tmp/foo.md",
        content: ("Entry at " + $val + ": started.")
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$output" | jq -e '.decision == "modify"' >/dev/null 2>&1; then
    new_content=$(echo "$output" | jq -r '.tool_input_override.content')
    if echo "$new_content" | grep -q "$NOW_FULL"; then
        assert_pass "drifted timestamp in content substituted"
    else
        assert_fail "content substitution failed, got $new_content"
    fi
else
    assert_fail "expected modify decision for content drift"
fi

# --- Test 3: timestamp within tolerance band → not substituted ---
INPUT=$(jq -nc --arg val "$NOW_FULL" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/archive-" + $val + ".md"),
        content: "hello"
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if [ -z "$output" ]; then
    assert_pass "in-band timestamp not substituted (silent)"
else
    assert_fail "expected silent exit, got $output"
fi

# --- Test 4: no timestamp at all → silent exit ---
INPUT=$(jq -nc '{
    tool_name: "Write",
    tool_input: {
        file_path: "/tmp/foo.md",
        content: "no timestamps anywhere here"
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if [ -z "$output" ]; then
    assert_pass "no timestamp present is silent"
else
    assert_fail "expected silent, got $output"
fi

# --- Test 5: advisory mode → stderr feedback, no substitution ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/log-" + $val + ".md"),
        content: "ok"
    }
}')
stdout_out=$(CC_TIMESTAMP_REWRITE_ADVISORY=1 printf '%s' "$INPUT" | CC_TIMESTAMP_REWRITE_ADVISORY=1 bash "$HOOK" 2>/dev/null)
stderr_out=$(CC_TIMESTAMP_REWRITE_ADVISORY=1 printf '%s' "$INPUT" | CC_TIMESTAMP_REWRITE_ADVISORY=1 bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$stdout_out" ] && echo "$stderr_out" | grep -q "TIMESTAMP DRIFT DETECTED"; then
    assert_pass "advisory mode emits stderr feedback only"
else
    assert_fail "advisory mode broke; stdout=$stdout_out stderr=$stderr_out"
fi

# --- Test 6: disable flag → silent exit ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/log-" + $val + ".md"),
        content: "ok"
    }
}')
output=$(CC_TIMESTAMP_REWRITE_DISABLE=1 printf '%s' "$INPUT" | CC_TIMESTAMP_REWRITE_DISABLE=1 bash "$HOOK" 2>&1)
if [ -z "$output" ]; then
    assert_pass "CC_TIMESTAMP_REWRITE_DISABLE=1 fully silences hook"
else
    assert_fail "disable flag did not silence, got $output"
fi

# --- Test 7: empty input → silent exit ---
output=$(printf '' | bash "$HOOK" 2>&1)
if [ -z "$output" ]; then
    assert_pass "empty stdin is silent"
else
    assert_fail "empty stdin should be silent, got $output"
fi

# --- Test 8: Edit tool → handled ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Edit",
    tool_input: {
        file_path: "/tmp/foo.md",
        old_string: "before",
        new_string: ("after " + $val)
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$output" | jq -e '.decision == "modify"' >/dev/null 2>&1; then
    assert_pass "Edit tool drifted new_string is substituted"
else
    assert_fail "Edit tool should be handled, got $output"
fi

# --- Test 9: tolerance band custom (1 minute) → smaller window ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/log-" + $val + ".md"),
        content: "ok"
    }
}')
output=$(CC_TIMESTAMP_REWRITE_DRIFT=1 printf '%s' "$INPUT" | CC_TIMESTAMP_REWRITE_DRIFT=1 bash "$HOOK" 2>/dev/null)
if echo "$output" | jq -e '.decision == "modify"' >/dev/null 2>&1; then
    assert_pass "custom drift tolerance respected"
else
    assert_fail "custom drift not honored, got $output"
fi

# --- Test 10: no tool_name → still processed if content present ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_input: {
        file_path: ("/tmp/log-" + $val + ".md"),
        content: "ok"
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$output" | jq -e '.decision == "modify"' >/dev/null 2>&1; then
    assert_pass "missing tool_name still triggers substitution"
else
    assert_fail "missing tool_name should still process, got $output"
fi

# --- Test 11: only file_path, no content → substitution on path alone ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/archive-" + $val + ".md")
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if echo "$output" | jq -e '.decision == "modify"' >/dev/null 2>&1; then
    assert_pass "file_path-only input substitutes correctly"
else
    assert_fail "file_path-only should work, got $output"
fi

# --- Test 12: substitution reason field references #60492 ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/log-" + $val + ".md"),
        content: "ok"
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
reason=$(echo "$output" | jq -r '.reason // empty')
if echo "$reason" | grep -q "60492"; then
    assert_pass "substitution reason cites #60492"
else
    assert_fail "reason missing #60492 reference, got: $reason"
fi

# --- Test 13: malformed JSON input → silent exit (no crash) ---
output=$(printf 'not valid json' | bash "$HOOK" 2>&1)
if [ -z "$output" ] || ! echo "$output" | grep -qi "error\|traceback"; then
    assert_pass "malformed input does not crash"
else
    assert_fail "malformed input produced error: $output"
fi

# --- Test 14: zero-length file_path field → silent if no content drift ---
INPUT=$(jq -nc '{
    tool_name: "Write",
    tool_input: {
        file_path: "",
        content: "no drifted timestamps here"
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
if [ -z "$output" ]; then
    assert_pass "empty path + clean content is silent"
else
    assert_fail "expected silent, got $output"
fi

# --- Test 15: stderr note emitted alongside stdout substitution ---
INPUT=$(jq -nc --arg val "$PAST_VALUE" '{
    tool_name: "Write",
    tool_input: {
        file_path: ("/tmp/log-" + $val + ".md"),
        content: "ok"
    }
}')
stderr_out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 >/dev/null)
if echo "$stderr_out" | grep -q "Timestamp substitution applied"; then
    assert_pass "stderr note accompanies substitution"
else
    assert_fail "stderr note missing, got: $stderr_out"
fi

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
