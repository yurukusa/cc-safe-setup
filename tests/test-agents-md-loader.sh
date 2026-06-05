#!/bin/bash
# Tests for agents-md-loader.sh — verify the SessionStart hook detects
# AGENTS.md, surfaces its content to the agent, and handles edge cases.

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/agents-md-loader.sh"
TMPROOT=$(mktemp -d)
trap "rm -rf $TMPROOT" EXIT

PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== agents-md-loader.sh tests ==="

# --- Test 1: No AGENTS.md → silent exit 0 ---
mkdir -p "$TMPROOT/case1"
cd "$TMPROOT/case1"
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no AGENTS.md → silent exit 0"
else
    assert_fail "expected silent exit 0, got rc=$rc output=$output"
fi

# --- Test 2: AGENTS.md in cwd → surfaces content ---
mkdir -p "$TMPROOT/case2"
cd "$TMPROOT/case2"
printf '# Test Project\n\nBuild: npm run build\nTest: npm test\n' > AGENTS.md
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "AGENTS.md detected" && echo "$output" | grep -q "npm run build"; then
    assert_pass "AGENTS.md in cwd → content surfaced in system-reminder"
else
    assert_fail "expected content in reminder, got rc=$rc output=$output"
fi

# --- Test 3: AGENTS.md in parent (walk up) ---
mkdir -p "$TMPROOT/case3/sub/deeper"
printf '# Parent Project\n\nMonorepo root\n' > "$TMPROOT/case3/AGENTS.md"
cd "$TMPROOT/case3/sub/deeper"
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "Parent Project"; then
    assert_pass "walks up the parent tree to find AGENTS.md"
else
    assert_fail "expected parent AGENTS.md found, got rc=$rc output=$output"
fi

# --- Test 4: Closest AGENTS.md wins (monorepo nested file) ---
mkdir -p "$TMPROOT/case4/packages/app"
printf '# Monorepo Root\n' > "$TMPROOT/case4/AGENTS.md"
printf '# Package App (closest wins)\n' > "$TMPROOT/case4/packages/app/AGENTS.md"
cd "$TMPROOT/case4/packages/app"
output=$(bash "$HOOK" 2>&1)
rc=$?
if echo "$output" | grep -q "Package App (closest wins)" && ! echo "$output" | grep -q "Monorepo Root"; then
    assert_pass "closest AGENTS.md (monorepo subdir) takes precedence"
else
    assert_fail "expected nested file to win, got: $output"
fi

# --- Test 5: SEARCH_PARENTS=0 only checks cwd ---
mkdir -p "$TMPROOT/case5/sub"
printf '# Parent\n' > "$TMPROOT/case5/AGENTS.md"
cd "$TMPROOT/case5/sub"
output=$(CC_AGENTS_MD_SEARCH_PARENTS=0 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_AGENTS_MD_SEARCH_PARENTS=0 → only cwd checked, silent"
else
    assert_fail "expected silent (no parent walk), got rc=$rc output=$output"
fi

# --- Test 6: Disable flag respected ---
mkdir -p "$TMPROOT/case6"
cd "$TMPROOT/case6"
printf '# Content\n' > AGENTS.md
output=$(CC_AGENTS_MD_LOADER_DISABLE=1 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "CC_AGENTS_MD_LOADER_DISABLE=1 silences the hook"
else
    assert_fail "expected silent disable, got rc=$rc output=$output"
fi

# --- Test 7: Truncation when file exceeds MAX_BYTES ---
mkdir -p "$TMPROOT/case7"
cd "$TMPROOT/case7"
# Create a 20KB file
head -c 20480 /dev/urandom | base64 > AGENTS.md
output=$(CC_AGENTS_MD_MAX_BYTES=1024 bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "truncated"; then
    assert_pass "files larger than MAX_BYTES are truncated with notice"
else
    assert_fail "expected truncation notice, got rc=$rc output=$output"
fi

# --- Test 8: Empty AGENTS.md → silent ---
mkdir -p "$TMPROOT/case8"
cd "$TMPROOT/case8"
touch AGENTS.md
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "empty AGENTS.md → silent no-op"
else
    assert_fail "expected silent on empty file, got rc=$rc output=$output"
fi

# --- Test 9: CLAUDE.md coexistence noted ---
mkdir -p "$TMPROOT/case9"
cd "$TMPROOT/case9"
printf '# Project context for all agents\n' > AGENTS.md
printf '# Claude-specific instructions\n' > CLAUDE.md
output=$(bash "$HOOK" 2>&1)
rc=$?
if echo "$output" | grep -q "CLAUDE.md is also present"; then
    assert_pass "CLAUDE.md coexistence is mentioned when both files present"
else
    assert_fail "expected CLAUDE.md mention, got: $output"
fi

# --- Test 10: AGENTS.md surfaced even without CLAUDE.md ---
mkdir -p "$TMPROOT/case10"
cd "$TMPROOT/case10"
printf '# Project only has AGENTS\n' > AGENTS.md
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "Project only has AGENTS" && ! echo "$output" | grep -q "CLAUDE.md is also present"; then
    assert_pass "AGENTS.md surfaced, no CLAUDE.md note when CLAUDE.md absent"
else
    assert_fail "unexpected output, got rc=$rc output=$output"
fi

# --- Test 11: Hook never blocks (always exits 0) ---
mkdir -p "$TMPROOT/case11"
cd "$TMPROOT/case11"
printf 'content' > AGENTS.md
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "SessionStart hook always exits 0 (non-blocking)"
else
    assert_fail "expected exit 0, got rc=$rc"
fi

# --- Test 12: Issue reference cited ---
mkdir -p "$TMPROOT/case12"
cd "$TMPROOT/case12"
printf '# content\n' > AGENTS.md
output=$(bash "$HOOK" 2>&1)
if echo "$output" | grep -q "claude-code#6235"; then
    assert_pass "reminder cites claude-code#6235 (the feature request)"
else
    assert_fail "expected #6235 citation in reminder"
fi

# --- Test 13: AGENTS.md path appears in BEGIN/END markers ---
mkdir -p "$TMPROOT/case13"
cd "$TMPROOT/case13"
printf '# content\n' > AGENTS.md
output=$(bash "$HOOK" 2>&1)
abs_path="$TMPROOT/case13/AGENTS.md"
if echo "$output" | grep -q "BEGIN $abs_path" && echo "$output" | grep -q "END $abs_path"; then
    assert_pass "BEGIN/END markers include absolute path"
else
    assert_fail "expected BEGIN/END markers with path"
fi

# --- Test 14: File size reported ---
mkdir -p "$TMPROOT/case14"
cd "$TMPROOT/case14"
printf 'exactly twenty bytes' > AGENTS.md  # 20 chars
output=$(bash "$HOOK" 2>&1)
if echo "$output" | grep -qE "20 bytes"; then
    assert_pass "file size reported in reminder"
else
    assert_fail "expected file size in reminder"
fi

# --- Test 15: Stops at git root ---
mkdir -p "$TMPROOT/case15/sub"
cd "$TMPROOT/case15"
git init -q 2>&1 > /dev/null
mkdir -p "$TMPROOT/case15/../outer"
printf '# Outer (should not be reached)\n' > "$TMPROOT/case15/../outer/AGENTS.md"
cd "$TMPROOT/case15/sub"
output=$(bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "search stops at git root (does not escape repo)"
else
    assert_fail "search should not escape git root, got: $output"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
