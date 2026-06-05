#!/bin/bash
# Tests for public-artefact-socratic-narrowing.sh
#
# Verifies the PreToolUse-hook behavior addressing #60226 (the structural-
# parent frame) and the @beq00000 clean-state worked example:
#   - Public-artefact emission (gh pr, gh issue, git commit, etc.) with
#     body length above threshold → exit 2, Socratic reminder
#   - Same artefact hash within window → exit 0 (re-emission passes through)
#   - Below-threshold body → exit 0 silent
#   - Non-public-artefact Bash → exit 0 silent
#   - Non-public-artefact file → exit 0 silent
#   - Public-artefact file (.github/, README, etc.) Write/Edit → gated
#   - Missing input → exit 0 silent
#   - Disable flag respected

set -uo pipefail

HOOK="$(dirname "$0")/../examples/public-artefact-socratic-narrowing.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Use an isolated state dir per run so tests are independent
STATE_DIR=$(mktemp -d -t cc-socratic-test-XXXXXX)
trap 'rm -rf "$STATE_DIR"' EXIT
export CC_SOCRATIC_STATE_DIR="$STATE_DIR"

# Helper to build a long body so the length-threshold doesn't filter it
LONG_BODY=$(printf 'This is a non-trivial PR body with multiple claims. %.0s' {1..10})

echo "=== public-artefact-socratic-narrowing.sh tests ==="

# --- Test 1: gh pr create with long body → blocks with reminder ---
INPUT=$(jq -nc --arg cmd "gh pr create --title 'Fix' --body '$LONG_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && echo "$output" | grep -q "PUBLIC-ARTEFACT EMISSION BOUNDARY"; then
    assert_pass "gh pr create with long body blocks + emits reminder"
else
    assert_fail "expected rc=2 + reminder, got rc=$rc output=$output"
fi

# --- Test 2: Same artefact hash within window → passes through ---
# (Same INPUT as test 1, run again — cache should hit)
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "same-hash re-emission within window passes through silently"
else
    assert_fail "expected silent pass on re-emission, got rc=$rc output=$output"
fi

# --- Test 3: Below-threshold body → silent ---
INPUT=$(jq -nc '{
    tool_name: "Bash",
    tool_input: {command: "git commit -m \"fix typo\""}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "below-threshold commit message is silent"
else
    assert_fail "expected silent on short body, got rc=$rc output=$output"
fi

# --- Test 4: Non-public-artefact Bash (e.g. ls) → silent ---
INPUT=$(jq -nc --arg cmd "ls -la /tmp" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "non-public-artefact Bash is silent"
else
    assert_fail "expected silent on non-public Bash, got rc=$rc output=$output"
fi

# --- Test 5: gh issue comment with long body → blocks ---
INPUT=$(jq -nc --arg cmd "gh issue comment 60226 --body '$LONG_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "gh issue comment with long body blocks"
else
    assert_fail "expected gh issue comment to be gated (rc=$rc)"
fi

# --- Test 6: git commit -m with long body → blocks ---
INPUT=$(jq -nc --arg cmd "git commit -m '$LONG_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "git commit with long message blocks"
else
    assert_fail "expected git commit to be gated (rc=$rc)"
fi

# --- Test 7: gh release create with long body → blocks ---
INPUT=$(jq -nc --arg cmd "gh release create v1.0 --notes '$LONG_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "gh release create blocks"
else
    assert_fail "expected gh release create to be gated (rc=$rc)"
fi

# --- Test 8: Write to .github/ workflow file with long content → blocks ---
BODY_GITHUB=$(printf 'workflow content with steps and jobs definitions. %.0s' {1..10})
INPUT=$(jq -nc --arg content "$BODY_GITHUB" '{
    tool_name: "Write",
    tool_input: {
        file_path: ".github/workflows/ci.yml",
        content: $content
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "Write to .github/ blocks"
else
    assert_fail "expected .github/ Write to be gated (rc=$rc)"
fi

# --- Test 9: Write to README.md with long content → blocks ---
BODY_README=$(printf 'project overview with installation and usage examples. %.0s' {1..10})
INPUT=$(jq -nc --arg content "$BODY_README" '{
    tool_name: "Write",
    tool_input: {
        file_path: "/repo/README.md",
        content: $content
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "Write to README.md blocks"
else
    assert_fail "expected README.md Write to be gated (rc=$rc)"
fi

# --- Test 10: Write to CHANGELOG.md with long content → blocks ---
BODY_CHANGELOG=$(printf 'release notes with breaking changes and migration paths. %.0s' {1..10})
INPUT=$(jq -nc --arg content "$BODY_CHANGELOG" '{
    tool_name: "Write",
    tool_input: {
        file_path: "/repo/CHANGELOG.md",
        content: $content
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "Write to CHANGELOG.md blocks"
else
    assert_fail "expected CHANGELOG.md Write to be gated (rc=$rc)"
fi

# --- Test 11: Edit on README.md with long new_string → blocks ---
BODY_EDIT=$(printf 'expanded section with new claims and clarifications. %.0s' {1..10})
INPUT=$(jq -nc --arg new "$BODY_EDIT" '{
    tool_name: "Edit",
    tool_input: {
        file_path: "/repo/README.md",
        old_string: "old",
        new_string: $new
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "Edit on README.md blocks"
else
    assert_fail "expected README.md Edit to be gated (rc=$rc)"
fi

# --- Test 12: Write to internal file (not a public artefact path) → silent ---
BODY_INTERNAL=$(printf 'internal utility code with private helpers. %.0s' {1..10})
INPUT=$(jq -nc --arg content "$BODY_INTERNAL" '{
    tool_name: "Write",
    tool_input: {
        file_path: "/repo/src/util.ts",
        content: $content
    }
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "Write to internal source file is silent"
else
    assert_fail "expected silent on src/, got rc=$rc output=$output"
fi

# --- Test 13: Missing tool_name → silent ---
INPUT='{"tool_input": {"command": "gh pr create --body x"}}'
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "missing tool_name is silent no-op"
else
    assert_fail "expected silent on missing tool_name, got rc=$rc output=$output"
fi

# --- Test 14: Empty input → silent ---
output=$(printf '' | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty input is silent no-op"
else
    assert_fail "expected silent on empty, got rc=$rc output=$output"
fi

# --- Test 15: CC_SOCRATIC_DISABLE=1 respected ---
INPUT=$(jq -nc --arg cmd "gh pr create --body '$LONG_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | CC_SOCRATIC_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_SOCRATIC_DISABLE=1 disables the gate"
else
    assert_fail "disable flag not respected (rc=$rc output=$output)"
fi

# --- Test 16: Reminder references #60226 ---
# Use distinct body to avoid the cache hit from earlier tests
DISTINCT_BODY=$(printf 'A different distinct body for cite test. %.0s' {1..10})
INPUT=$(jq -nc --arg cmd "gh pr create --body '$DISTINCT_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
if echo "$output" | grep -q "#60226"; then
    assert_pass "reminder cites #60226"
else
    assert_fail "expected #60226 reference in reminder (got: $output)"
fi

# --- Test 17: Reminder references the Socratic-narrowing form ---
DISTINCT_BODY2=$(printf 'Yet another distinct body for socratic test. %.0s' {1..10})
INPUT=$(jq -nc --arg cmd "gh pr create --body '$DISTINCT_BODY2'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
if echo "$output" | grep -qi "gradient"; then
    assert_pass "reminder names the gradient framing"
else
    assert_fail "expected 'gradient' framing in reminder"
fi

# --- Test 18: Hash cache expires (TTL=1, sleep 2, re-fires) ---
DISTINCT_BODY3=$(printf 'Cache TTL expiry body. %.0s' {1..10})
INPUT=$(jq -nc --arg cmd "gh pr create --body '$DISTINCT_BODY3'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | CC_SOCRATIC_CACHE_TTL_SECONDS=1 bash "$HOOK" 2>&1)
rc1=$?
sleep 2
output=$(printf '%s' "$INPUT" | CC_SOCRATIC_CACHE_TTL_SECONDS=1 bash "$HOOK" 2>&1)
rc2=$?
if [ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ]; then
    assert_pass "cache entry expires past TTL (re-fires after window)"
else
    assert_fail "TTL not honored: first=$rc1 second=$rc2"
fi

# --- Test 19: Different artefact body → different hash → re-fires ---
BODY_A=$(printf 'Body A content for hash uniqueness. %.0s' {1..10})
BODY_B=$(printf 'Body B content totally different. %.0s' {1..10})
INPUT_A=$(jq -nc --arg cmd "gh pr create --body '$BODY_A'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
INPUT_B=$(jq -nc --arg cmd "gh pr create --body '$BODY_B'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
printf '%s' "$INPUT_A" | bash "$HOOK" >/dev/null 2>&1
rc=$(printf '%s' "$INPUT_B" | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$rc" -eq 2 ]; then
    assert_pass "different content (different hash) re-fires gate"
else
    assert_fail "expected re-fire on different content, got rc=$rc"
fi

# --- Test 20: gh gist create with long body → blocks ---
INPUT=$(jq -nc --arg cmd "gh gist create --public --desc 'memo' -f notes.md $LONG_BODY" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "gh gist create blocks"
else
    assert_fail "expected gh gist create to be gated (rc=$rc)"
fi

# --- Test 21: git tag -a with long body → blocks ---
INPUT=$(jq -nc --arg cmd "git tag -a v2.0 -m '$LONG_BODY'" '{
    tool_name: "Bash",
    tool_input: {command: $cmd}
}')
output=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
    assert_pass "git tag -a with long message blocks"
else
    assert_fail "expected git tag to be gated (rc=$rc)"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
