#!/bin/bash
# Tests for subagent-destructive-git-guard.sh (Issue #57463 / #46444 / #53765 prevention)
HOOK="examples/subagent-destructive-git-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: Empty prompt should silently pass
OUT=$(echo '{"tool_input":{"prompt":""}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "empty prompt no warning" "$OUT" "destructive-git boundary"
assert_exit "empty prompt exit 0" "$RC" "0"

# Test 2: Vague prompt should warn on all 3 checks
OUT=$(echo '{"tool_input":{"prompt":"please rename Tailwind classes across all .tsx files"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_contains "vague warns destructive forbidden" "$OUT" "Destructive git commands not forbidden"
assert_contains "vague warns safe alternative" "$OUT" "No safe alternative named"
assert_contains "vague warns working tree check" "$OUT" "No working-tree state check"
assert_contains "vague references 57463" "$OUT" "#57463"
assert_contains "vague references 46444" "$OUT" "#46444"
assert_contains "vague references 53765" "$OUT" "#53765"
assert_exit "vague exit 0 advisory" "$RC" "0"

# Test 3: Destructive forbidden named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Do not use git checkout or git reset. Rename classes."}}' | bash "$HOOK" 2>&1)
assert_not_contains "destructive only no destructive warning" "$OUT" "Destructive git commands not forbidden"
assert_contains "destructive only warns alternative" "$OUT" "No safe alternative named"
assert_contains "destructive only warns tree check" "$OUT" "No working-tree state check"

# Test 4: Safe alternative named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Use git stash before any change. Rename classes."}}' | bash "$HOOK" 2>&1)
assert_contains "alternative only warns destructive" "$OUT" "Destructive git commands not forbidden"
assert_not_contains "alternative only no alternative warning" "$OUT" "No safe alternative named"
assert_contains "alternative only warns tree check" "$OUT" "No working-tree state check"

# Test 5: Working tree check named, other 2 missing
OUT=$(echo '{"tool_input":{"prompt":"Run git status first before any change. Rename classes."}}' | bash "$HOOK" 2>&1)
assert_contains "tree check only warns destructive" "$OUT" "Destructive git commands not forbidden"
assert_contains "tree check only warns alternative" "$OUT" "No safe alternative named"
assert_not_contains "tree check only no tree check warning" "$OUT" "No working-tree state check"

# Test 6: All 3 boundary instructions present, no warning
OUT=$(echo '{"tool_input":{"prompt":"Do not use git checkout, git reset, or git restore. Use git stash before any change. Run git status first to verify working tree state. Rename Tailwind classes across .tsx files."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "well-formed no warning" "$OUT" "destructive-git boundary"
assert_exit "well-formed exit 0" "$RC" "0"

# Test 7: Japanese prompt with all 3 instructions, no warning
OUT=$(echo '{"tool_input":{"prompt":"git checkout / git reset / git restore は禁止。stash の利用を優先。git status を最初に実行して作業の場の状態を確認してから、Tailwind class を rename する。"}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "Japanese well-formed no warning" "$OUT" "destructive-git boundary"
assert_exit "Japanese well-formed exit 0" "$RC" "0"

# Test 8: Strict mode blocks vague prompts
OUT=$(echo '{"tool_input":{"prompt":"rename classes"}}' | CC_SUBAGENT_DESTRUCTIVE_GIT_REQUIRE_ALL=1 bash "$HOOK" 2>&1)
RC=$?
assert_contains "strict mode warns" "$OUT" "destructive-git boundary"
assert_exit "strict mode blocks (exit 2)" "$RC" "2"

# Test 9: Missing prompt field should silently pass
OUT=$(echo '{}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "missing prompt no warning" "$OUT" "destructive-git boundary"
assert_exit "missing prompt exit 0" "$RC" "0"

# Test 10: Strict mode passes when boundary is set
OUT=$(echo '{"tool_input":{"prompt":"Do not use git checkout. Use git stash. Check git status first. Rename."}}' | CC_SUBAGENT_DESTRUCTIVE_GIT_REQUIRE_ALL=1 bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "strict well-formed no warning" "$OUT" "destructive-git boundary"
assert_exit "strict well-formed exit 0" "$RC" "0"

# Test 11: "destructive git" general phrase satisfies check 1
OUT=$(echo '{"tool_input":{"prompt":"No destructive git commands allowed. Use git stash. Check git status first."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "general phrase satisfies destructive check" "$OUT" "Destructive git commands not forbidden"

# Test 12: "ask the parent before" satisfies safe alternative check
OUT=$(echo '{"tool_input":{"prompt":"Do not use git checkout. Ask the parent before any destructive operation. Check git status first."}}' | bash "$HOOK" 2>&1)
RC=$?
assert_not_contains "ask parent satisfies alternative" "$OUT" "No safe alternative named"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
