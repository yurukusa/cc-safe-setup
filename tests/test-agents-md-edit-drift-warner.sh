#!/bin/bash
# Tests for agents-md-edit-drift-warner.sh
HOOK="examples/agents-md-edit-drift-warner.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in output)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in output)"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$PWD/$HOOK"

mk_input() {
    local tool="$1" path="$2"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path"
}

# Test 1: Non-Edit tool → silent
OUT=$(mk_input "Bash" "/tmp/foo/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "non-Edit tool silent" "$OUT" "drift"
assert_exit "non-Edit tool exit 0" "$RC" "0"

# Test 2: Non-instruction file → silent
echo "x" > "$TMPDIR/README.md"
OUT=$(mk_input "Edit" "$TMPDIR/README.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "non-instruction file silent" "$OUT" "drift"
assert_exit "non-instruction file exit 0" "$RC" "0"

# Test 3: CLAUDE.md edited, no AGENTS.md sibling → softer note
mkdir -p "$TMPDIR/t3"
echo "instructions" > "$TMPDIR/t3/CLAUDE.md"
OUT=$(mk_input "Edit" "$TMPDIR/t3/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "no sibling note" "$OUT" "No sibling AGENTS.md found"
assert_contains "sibling-tool list mentioned" "$OUT" "Codex"
assert_exit "no sibling exit 0" "$RC" "0"

# Test 4: AGENTS.md edited, no CLAUDE.md sibling → softer note
mkdir -p "$TMPDIR/t4"
echo "instructions" > "$TMPDIR/t4/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t4/AGENTS.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "no claude sibling note" "$OUT" "No sibling CLAUDE.md found"
assert_contains "sibling tool is Claude Code" "$OUT" "Claude Code"
assert_exit "no claude sibling exit 0" "$RC" "0"

# Test 5: Both files exist, identical content → silent (just synced)
mkdir -p "$TMPDIR/t5"
echo "same content" > "$TMPDIR/t5/CLAUDE.md"
echo "same content" > "$TMPDIR/t5/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t5/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "identical content silent" "$OUT" "Drift detected"
assert_exit "identical content exit 0" "$RC" "0"

# Test 6: Both files exist, different content → drift warning
mkdir -p "$TMPDIR/t6"
echo "updated claude" > "$TMPDIR/t6/CLAUDE.md"
echo "stale agents" > "$TMPDIR/t6/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t6/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "drift detected" "$OUT" "Drift detected"
assert_contains "cites cluster 3" "$OUT" "Cluster 3"
assert_contains "cites #6235" "$OUT" "#6235"
assert_contains "lists three options" "$OUT" "Mirror the edit"
assert_contains "lists symlink option" "$OUT" "Symlink"
assert_contains "cites PR #377 companion" "$OUT" "PR #377"
assert_exit "drift detected exit 0" "$RC" "0"

# Test 7: Symlinked siblings → silent (no drift possible)
mkdir -p "$TMPDIR/t7"
echo "shared" > "$TMPDIR/t7/CLAUDE.md"
ln -sf CLAUDE.md "$TMPDIR/t7/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t7/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "symlink silent" "$OUT" "Drift detected"
assert_exit "symlink exit 0" "$RC" "0"

# Test 8: Disable env → silent even with drift
mkdir -p "$TMPDIR/t8"
echo "claude updated" > "$TMPDIR/t8/CLAUDE.md"
echo "agents stale" > "$TMPDIR/t8/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t8/CLAUDE.md" | CC_AGENTS_MD_DRIFT_WARN_DISABLE=1 bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "disable env silences" "$OUT" "Drift detected"
assert_exit "disable env exit 0" "$RC" "0"

# Test 9: Quiet env → one-line note only
mkdir -p "$TMPDIR/t9"
echo "claude updated" > "$TMPDIR/t9/CLAUDE.md"
echo "agents stale" > "$TMPDIR/t9/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t9/CLAUDE.md" | CC_AGENTS_MD_DRIFT_WARN_QUIET=1 bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "quiet emits one-liner" "$OUT" "Drift: CLAUDE.md edited"
assert_not_contains "quiet suppresses verbose advisory" "$OUT" "Three reconciliation options"
assert_exit "quiet env exit 0" "$RC" "0"

# Test 10: Write tool also fires
mkdir -p "$TMPDIR/t10"
echo "claude updated" > "$TMPDIR/t10/CLAUDE.md"
echo "agents stale" > "$TMPDIR/t10/AGENTS.md"
OUT=$(mk_input "Write" "$TMPDIR/t10/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "Write tool fires" "$OUT" "Drift detected"
assert_exit "Write tool exit 0" "$RC" "0"

# Test 11: MultiEdit tool also fires
mkdir -p "$TMPDIR/t11"
echo "claude updated" > "$TMPDIR/t11/CLAUDE.md"
echo "agents stale" > "$TMPDIR/t11/AGENTS.md"
OUT=$(mk_input "MultiEdit" "$TMPDIR/t11/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "MultiEdit tool fires" "$OUT" "Drift detected"
assert_exit "MultiEdit tool exit 0" "$RC" "0"

# Test 12: AGENTS.md edited, CLAUDE.md drifts → warning
mkdir -p "$TMPDIR/t12"
echo "claude stale" > "$TMPDIR/t12/CLAUDE.md"
echo "agents updated" > "$TMPDIR/t12/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t12/AGENTS.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "agents edit detects drift" "$OUT" "Drift detected"
assert_contains "names Claude Code as sibling tool" "$OUT" "Claude Code"
assert_exit "agents edit exit 0" "$RC" "0"

# Test 13: Cross-mounted .claude/CLAUDE.md edit, .agents/AGENTS.md exists → drift
mkdir -p "$TMPDIR/t13/.claude" "$TMPDIR/t13/.agents"
echo "claude updated" > "$TMPDIR/t13/.claude/CLAUDE.md"
echo "agents stale" > "$TMPDIR/t13/.agents/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t13/.claude/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "cross-mount drift" "$OUT" "Drift detected"
assert_contains "cross-mount sibling path" "$OUT" ".agents/AGENTS.md"
assert_exit "cross-mount exit 0" "$RC" "0"

# Test 14: Cross-mounted with no sibling → softer note
mkdir -p "$TMPDIR/t14/.claude"
echo "claude updated" > "$TMPDIR/t14/.claude/CLAUDE.md"
OUT=$(mk_input "Edit" "$TMPDIR/t14/.claude/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "cross-mount no sibling softer note" "$OUT" "No sibling"
assert_exit "cross-mount no sibling exit 0" "$RC" "0"

# Test 15: file_path basename matches but is in unrelated directory (e.g., docs/CLAUDE.md)
# — still treated as instruction file because basename match is the trigger
mkdir -p "$TMPDIR/t15/docs"
echo "doc instructions" > "$TMPDIR/t15/docs/CLAUDE.md"
OUT=$(mk_input "Edit" "$TMPDIR/t15/docs/CLAUDE.md" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_contains "docs CLAUDE.md basename match" "$OUT" "No sibling AGENTS.md found"
assert_exit "docs CLAUDE.md exit 0" "$RC" "0"

# Test 16: Empty input → silent
OUT=$(echo "" | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "empty input silent" "$OUT" "drift"
assert_exit "empty input exit 0" "$RC" "0"

# Test 17: Missing file_path in input → silent
OUT=$(printf '{"tool_name":"Edit","tool_input":{}}' | bash "$HOOK_ABS" 2>&1); RC=$?
assert_not_contains "no file_path silent" "$OUT" "drift"
assert_exit "no file_path exit 0" "$RC" "0"

# Test 18: Drift warning includes byte counts of both files
mkdir -p "$TMPDIR/t18"
echo "claude has new content here that is longer" > "$TMPDIR/t18/CLAUDE.md"
echo "old" > "$TMPDIR/t18/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t18/CLAUDE.md" | bash "$HOOK_ABS" 2>&1)
assert_contains "drift mentions edited bytes" "$OUT" "bytes"
assert_contains "drift mentions NOT updated" "$OUT" "NOT updated"

# Test 19: Edit tool when sibling has identical content (just synced manually) → silent
mkdir -p "$TMPDIR/t19"
echo "same" > "$TMPDIR/t19/CLAUDE.md"
echo "same" > "$TMPDIR/t19/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t19/CLAUDE.md" | bash "$HOOK_ABS" 2>&1)
assert_not_contains "post-sync edit silent" "$OUT" "Drift detected"

# Test 20: Drift warning mentions reconciliation step concretely (ln -sf)
mkdir -p "$TMPDIR/t20"
echo "claude" > "$TMPDIR/t20/CLAUDE.md"
echo "agents" > "$TMPDIR/t20/AGENTS.md"
OUT=$(mk_input "Edit" "$TMPDIR/t20/CLAUDE.md" | bash "$HOOK_ABS" 2>&1)
assert_contains "advisory mentions ln -sf" "$OUT" "ln -sf"

echo ""
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
