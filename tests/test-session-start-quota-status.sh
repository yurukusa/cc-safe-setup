#!/bin/bash
# Tests for session-start-quota-status.sh — verifies the SessionStart
# hook computes rolling 5-hour / 7-day token usage from local JSONL
# transcripts and surfaces estimated API-equivalent cost.

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/session-start-quota-status.sh"
TMPROOT=$(mktemp -d)
trap "find $TMPROOT -mindepth 1 -delete 2>/dev/null; rmdir $TMPROOT 2>/dev/null" EXIT

PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Helper: create a JSONL entry with the given model and token counts
make_entry() {
    local model="$1" input="$2" output="$3" cache_read="$4" cache_write="$5"
    jq -nc \
        --arg model "$model" \
        --argjson input "$input" \
        --argjson output "$output" \
        --argjson cache_read "$cache_read" \
        --argjson cache_write "$cache_write" \
        '{
            message: {
                role: "assistant",
                model: $model,
                usage: {
                    input_tokens: $input,
                    output_tokens: $output,
                    cache_read_input_tokens: $cache_read,
                    cache_creation_input_tokens: $cache_write
                }
            }
        }'
}

echo "=== session-start-quota-status.sh tests ==="

# --- Test 1: No projects dir → silent ---
output=$(CC_QUOTA_PROJECTS_DIR=/nonexistent bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing projects dir → silent exit 0"
else
    assert_fail "expected silent, got rc=$rc output=$output"
fi

# --- Test 2: Empty projects dir → silent ---
mkdir -p "$TMPROOT/case2"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case2" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty projects dir → silent exit 0"
else
    assert_fail "expected silent on empty dir, got rc=$rc output=$output"
fi

# --- Test 3: Disable flag respected ---
mkdir -p "$TMPROOT/case3/proj1"
make_entry "claude-opus-4-7" 1000 5000 100000 10000 > "$TMPROOT/case3/proj1/session.jsonl"
output=$(CC_QUOTA_STATUS_DISABLE=1 CC_QUOTA_PROJECTS_DIR="$TMPROOT/case3" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_QUOTA_STATUS_DISABLE=1 silences hook"
else
    assert_fail "expected silent disable, got rc=$rc output=$output"
fi

# --- Test 4: Recent activity → reminder emitted ---
mkdir -p "$TMPROOT/case4/proj1"
make_entry "claude-opus-4-7" 1000 5000 100000 10000 > "$TMPROOT/case4/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case4" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "QUOTA STATUS"; then
    assert_pass "recent activity → reminder surfaced"
else
    assert_fail "expected QUOTA STATUS reminder, got rc=$rc output=$output"
fi

# --- Test 5: Threshold warning fires when cost exceeds 5h threshold ---
mkdir -p "$TMPROOT/case5/proj1"
# Large opus usage → ~$500+ cost
make_entry "claude-opus-4-7" 100000 100000 1000000 100000 > "$TMPROOT/case5/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case5" CC_QUOTA_5H_WARN_USD=1 bash "$HOOK" 2>&1)
rc=$?
if echo "$output" | grep -q "WARN: above CC_QUOTA_5H_WARN_USD"; then
    assert_pass "5h threshold warning fires when cost exceeds limit"
else
    assert_fail "expected 5h WARN, got: $output"
fi

# --- Test 6: No threshold warning when cost is low ---
mkdir -p "$TMPROOT/case6/proj1"
make_entry "claude-haiku-4-5" 100 200 1000 500 > "$TMPROOT/case6/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case6" CC_QUOTA_5H_WARN_USD=100 CC_QUOTA_WEEKLY_WARN_USD=1000 bash "$HOOK" 2>&1)
rc=$?
if ! echo "$output" | grep -q "WARN:"; then
    assert_pass "low-cost activity does not trigger WARN"
else
    assert_fail "unexpected WARN, got: $output"
fi

# --- Test 7: Multiple model families aggregated ---
mkdir -p "$TMPROOT/case7/proj1" "$TMPROOT/case7/proj2"
make_entry "claude-opus-4-7" 1000 5000 100000 10000 > "$TMPROOT/case7/proj1/session.jsonl"
make_entry "claude-sonnet-4-6" 2000 8000 200000 20000 >> "$TMPROOT/case7/proj1/session.jsonl"
make_entry "claude-haiku-4-5" 500 1500 50000 5000 > "$TMPROOT/case7/proj2/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case7" bash "$HOOK" 2>&1)
rc=$?
if echo "$output" | grep -q "opus" && echo "$output" | grep -q "sonnet" && echo "$output" | grep -q "haiku"; then
    assert_pass "multiple model families aggregated and surfaced"
else
    assert_fail "expected opus/sonnet/haiku in output, got: $output"
fi

# --- Test 8: Reminder cites the three Issues ---
mkdir -p "$TMPROOT/case8/proj1"
make_entry "claude-sonnet-4-6" 1000 5000 100000 10000 > "$TMPROOT/case8/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case8" bash "$HOOK" 2>&1)
if echo "$output" | grep -q "16157" && echo "$output" | grep -q "38335" && echo "$output" | grep -q "29579"; then
    assert_pass "reminder cites the three quota Issues"
else
    assert_fail "expected #16157, #38335, #29579 in reminder"
fi

# --- Test 9: Reminder names Pool 2 / June 15 context ---
mkdir -p "$TMPROOT/case9/proj1"
make_entry "claude-sonnet-4-6" 1000 5000 100000 10000 > "$TMPROOT/case9/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case9" bash "$HOOK" 2>&1)
if echo "$output" | grep -q "Pool 2" && echo "$output" | grep -q "June 15"; then
    assert_pass "reminder mentions Pool 2 / June 15 context for sub-tier comparison"
else
    assert_fail "expected Pool 2 / June 15 mention, got: $output"
fi

# --- Test 10: Disable escape mentioned ---
mkdir -p "$TMPROOT/case10/proj1"
make_entry "claude-sonnet-4-6" 1000 5000 100000 10000 > "$TMPROOT/case10/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case10" bash "$HOOK" 2>&1)
if echo "$output" | grep -q "CC_QUOTA_STATUS_DISABLE=1"; then
    assert_pass "reminder names the disable escape"
else
    assert_fail "expected CC_QUOTA_STATUS_DISABLE=1 mention"
fi

# --- Test 11: Always exits 0 (non-blocking) ---
mkdir -p "$TMPROOT/case11/proj1"
make_entry "claude-opus-4-7" 100000000 100000000 1000000000 100000000 > "$TMPROOT/case11/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case11" CC_QUOTA_5H_WARN_USD=0.01 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "always exits 0 (SessionStart non-blocking contract)"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 12: File size formatting (k/M suffix) ---
mkdir -p "$TMPROOT/case12/proj1"
make_entry "claude-opus-4-7" 1500 8000000 5000000000 200000 > "$TMPROOT/case12/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case12" bash "$HOOK" 2>&1)
if echo "$output" | grep -qE "[0-9]+\.[0-9]+M" && echo "$output" | grep -qE "[0-9]+\.[0-9]+k"; then
    assert_pass "token counts formatted with k/M suffixes"
else
    assert_fail "expected k/M formatted numbers, got: $output"
fi

# --- Test 13: Old JSONL outside 5h window still in 7d window ---
mkdir -p "$TMPROOT/case13/proj1"
make_entry "claude-sonnet-4-6" 5000 10000 50000 5000 > "$TMPROOT/case13/proj1/session.jsonl"
# Set mtime to 6 hours ago
touch -d '6 hours ago' "$TMPROOT/case13/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case13" bash "$HOOK" 2>&1)
# Should be no activity in 5h window, but show in weekly
if echo "$output" | grep -q "no activity in this window"; then
    assert_pass "5h window correctly excludes 6h-old files"
else
    assert_fail "expected 5h window to exclude 6h-old file, got: $output"
fi

# --- Test 14: Custom thresholds respected ---
mkdir -p "$TMPROOT/case14/proj1"
make_entry "claude-sonnet-4-6" 1000 2000 10000 1000 > "$TMPROOT/case14/proj1/session.jsonl"
# Test with very low threshold that should trigger
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case14" CC_QUOTA_5H_WARN_USD=0.01 bash "$HOOK" 2>&1)
if echo "$output" | grep -q "WARN: above CC_QUOTA_5H_WARN_USD threshold of \$0.01"; then
    assert_pass "custom 5h threshold (\$0.01) honored"
else
    assert_fail "expected custom threshold in WARN, got: $output"
fi

# --- Test 15: No activity in either window → silent ---
mkdir -p "$TMPROOT/case15/proj1"
make_entry "claude-sonnet-4-6" 1000 2000 10000 1000 > "$TMPROOT/case15/proj1/session.jsonl"
# Set mtime to 8 days ago (outside both windows)
touch -d '8 days ago' "$TMPROOT/case15/proj1/session.jsonl"
output=$(CC_QUOTA_PROJECTS_DIR="$TMPROOT/case15" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no activity in either window → silent exit 0"
else
    assert_fail "expected silent when nothing in windows, got: $output"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
