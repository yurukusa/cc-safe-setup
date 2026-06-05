#!/bin/bash
# Tests for ai-slop-punctuation-arrest.sh

set -uo pipefail

HOOK="$(dirname "$0")/../examples/ai-slop-punctuation-arrest.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

STATE_DIR=$(mktemp -d -t cc-aislop-test-XXXXXX)
trap 'rm -rf "$STATE_DIR"' EXIT
export CC_AI_SLOP_STATE_DIR="$STATE_DIR"
export CC_AI_SLOP_ENABLE=1   # gate is opt-in; enable it for the block-mode tests

echo "=== ai-slop-punctuation-arrest.sh tests ==="

# --- Test 1: em-dash in markdown → blocks ---
INPUT=$(jq -nc --arg c "This sentence has an em-dash — yes it does." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/README.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "AI-SLOP PUNCTUATION DETECTED"; then
    assert_pass "em-dash in .md blocks with reminder"
else
    assert_fail "expected rc=2 + reminder, got rc=$rc output=$output"
fi

# --- Test 2: double-hyphen substitute (space form) → blocks ---
INPUT=$(jq -nc --arg c "The model uses double hyphens -- like this -- as substitutes." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/doc.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "double-hyphen substitute in .md blocks"
else
    assert_fail "expected gate on double-hyphen, got rc=$rc"
fi

# --- Test 3: attached double-hyphen (word--word) → blocks ---
INPUT=$(jq -nc --arg c "This is the case--without spaces--mostly." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/notes.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "attached double-hyphen blocks"
else
    assert_fail "expected gate on attached --, got rc=$rc"
fi

# --- Test 4: clean markdown → silent ---
INPUT=$(jq -nc --arg c "This sentence has no offending punctuation. It uses commas, periods, and semicolons." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/clean.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "clean markdown is silent"
else
    assert_fail "expected silent on clean text, got rc=$rc output=$output"
fi

# --- Test 5: non-markdown file (.ts) → silent even with em-dash ---
INPUT=$(jq -nc --arg c "// comment with em-dash — does not gate in code files" '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/src/util.ts", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-markdown file is silent"
else
    assert_fail "expected silent on .ts, got rc=$rc"
fi

# --- Test 6: em-dash inside fenced code block in .md → silent (code stripped) ---
INPUT=$(jq -nc --arg c $'Some prose.\n\n```bash\necho "—" --flag\n```\n\nMore clean prose.' '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/clean2.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "em-dash inside fenced code block is silent (code stripped)"
else
    assert_fail "expected silent inside code block, got rc=$rc output=$output"
fi

# --- Test 7: double-hyphen inside inline code `--flag` → silent ---
INPUT=$(jq -nc --arg c "Run \`cargo build --release\` to build the project. The model now respects boundaries." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/howto.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "double-hyphen inside inline code is silent"
else
    assert_fail "expected silent on inline code flag, got rc=$rc output=$output"
fi

# --- Test 8: Edit operation with em-dash in new_string → blocks ---
INPUT=$(jq -nc --arg c "Adding a sentence with an em-dash — for emphasis." '{
    tool_name: "Edit",
    tool_input: {
        file_path: "/repo/README.md",
        old_string: "old",
        new_string: $c
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "Edit with em-dash in new_string blocks"
else
    assert_fail "expected Edit to be gated (rc=$rc)"
fi

# --- Test 9: missing tool_name → silent ---
INPUT='{"tool_input": {"file_path": "/repo/x.md", "content": "—"}}'
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing tool_name is silent no-op"
else
    assert_fail "expected silent on missing tool_name, got rc=$rc"
fi

# --- Test 10: empty input → silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input is silent no-op"
else
    assert_fail "expected silent on empty, got rc=$rc"
fi

# --- Test 11: CC_AI_SLOP_DISABLE=1 respected ---
INPUT=$(jq -nc --arg c "em-dash —" '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/x.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | CC_AI_SLOP_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_AI_SLOP_DISABLE=1 disables the gate"
else
    assert_fail "disable flag not respected (rc=$rc)"
fi

# --- Test 12: reminder cites #60226 ---
INPUT=$(jq -nc --arg c "an em-dash — present in distinct content for citation test" '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/cite.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "#60226"; then
    assert_pass "reminder cites #60226"
else
    assert_fail "expected #60226 reference (got: $output)"
fi

# --- Test 13: reminder names substitution-by-default mechanism ---
INPUT=$(jq -nc --arg c "em-dash — yet another distinct content for the substitution mechanism test" '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/sub.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -qi "substitution"; then
    assert_pass "reminder names the substitution-by-default mechanism"
else
    assert_fail "expected 'substitution' in reminder"
fi

# --- Test 14: same-hash re-emission passes through ---
INPUT=$(jq -nc --arg c "deliberate em-dash — for hash-cache re-emit test" '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/cache.md", content: $c}
}')
# First call: should block
output1=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc1=$?
# Second call: same content, should pass through
output2=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc2=$?
if [ "$rc1" -eq 2 ] && [ "$rc2" -eq 0 ]; then
    assert_pass "same-hash re-emission passes through after first block"
else
    assert_fail "cache not honored: first=$rc1 second=$rc2"
fi

# --- Test 15: range notation 5--10 in prose → blocks (intentional) ---
INPUT=$(jq -nc --arg c "The range is 5--10 items per page, with multiple sentences." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/range.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "range notation 5--10 in prose blocks (operator can override)"
else
    assert_fail "expected gate on attached range, got rc=$rc"
fi

# --- Test 16: .mdx file with em-dash → blocks ---
INPUT=$(jq -nc --arg c "MDX content with an em-dash — yes here." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/page.mdx", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass ".mdx file is gated"
else
    assert_fail "expected .mdx to be gated (rc=$rc)"
fi

# --- Test 17: .txt file with em-dash → blocks ---
INPUT=$(jq -nc --arg c "Plain text with em-dash — for testing." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/notes.txt", content: $c}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass ".txt file is gated"
else
    assert_fail "expected .txt to be gated (rc=$rc)"
fi

# --- Test 18: custom CC_AI_SLOP_PUNCT_PATTERNS overrides default ---
INPUT=$(jq -nc --arg c "Sentence with em-dash — only, no double hyphens here." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/custom.md", content: $c}
}')
# Restrict pattern to just em-dash, should still block
output=$(printf '%s' "$INPUT" | CC_AI_SLOP_PUNCT_PATTERNS='—' bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "custom CC_AI_SLOP_PUNCT_PATTERNS=— still catches em-dash"
else
    assert_fail "expected custom pattern to gate em-dash, got rc=$rc"
fi

# --- Test 19: custom file pattern narrows scope ---
INPUT=$(jq -nc --arg c "em-dash — present in a non-default file extension" '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/blog.html", content: $c}
}')
# Default would not gate .html. With custom pattern including html, should gate.
output=$(printf '%s' "$INPUT" | CC_AI_SLOP_FILE_PATTERNS='\.html$' bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "custom file pattern extends scope to .html"
else
    assert_fail "expected custom file pattern to gate .html, got rc=$rc"
fi
INPUT=$(jq -nc --arg c "This sentence has an em-dash — yes it does." '{
    tool_name: "Write",
    tool_input: {file_path: "/repo/README.md", content: $c}
}')
output=$(printf '%s' "$INPUT" | env -u CC_AI_SLOP_ENABLE bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "gate is off by default (CC_AI_SLOP_ENABLE unset → silent pass-through)"
else
    assert_fail "expected silent no-op without CC_AI_SLOP_ENABLE, got rc=$rc output=$output"
fi
echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
