#!/bin/bash
# Tests for bash-allowlist-secondary-check.sh (Issue #56117 prevention)
HOOK="examples/bash-allowlist-secondary-check.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  output: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; echo "  output: $2"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Use a temp directory with a controlled settings.json so the test does not
# depend on the host's user-level ~/.claude/settings.json.
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/.claude"
HOOK_ABS="$(pwd)/$HOOK"

cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git diff)",
      "Bash(git log:*)",
      "Bash(git status)",
      "Bash(npm test:*)",
      "Read(*)"
    ]
  }
}
EOF

# Avoid leaking the host's user-level settings into the matcher.
export HOME_BACKUP="$HOME"
export HOME="$TMPDIR"

cd "$TMPDIR" || exit 1

# Test 1: empty command — silent pass
OUT=$(echo '{"tool_input":{"command":""}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "empty command no warning" "$OUT" "not matched"
assert_exit "empty command exit 0" "$RC" "0"

# Test 2: exact match
OUT=$(echo '{"tool_input":{"command":"git diff"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "exact match no warning" "$OUT" "not matched"
assert_exit "exact match exit 0" "$RC" "0"

# Test 3: prefix match for "git log:*"
OUT=$(echo '{"tool_input":{"command":"git log -10 --oneline"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "prefix match no warning" "$OUT" "not matched"
assert_exit "prefix match exit 0" "$RC" "0"

# Test 4: prefix match for "npm test:*"
OUT=$(echo '{"tool_input":{"command":"npm test --watch"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "npm test prefix no warning" "$OUT" "not matched"
assert_exit "npm test prefix exit 0" "$RC" "0"

# Test 5: not in allowlist — Issue #56117 case (git push)
OUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "git push warns" "$OUT" "not matched by any settings.json allow pattern"
assert_contains "git push references issue" "$OUT" "#56117"
assert_contains "git push includes the command" "$OUT" "git push origin main"
assert_exit "git push exit 0 advisory" "$RC" "0"

# Test 6: not in allowlist — git add (also #56117 case)
OUT=$(echo '{"tool_input":{"command":"git add -A"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "git add warns" "$OUT" "not matched"
assert_exit "git add advisory exit 0" "$RC" "0"

# Test 7: strict mode blocks
OUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | CC_BASH_ALLOWLIST_STRICT=1 bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "strict still warns" "$OUT" "not matched"
assert_exit "strict mode exit 2" "$RC" "2"

# Test 8: quiet mode silences warning but still blocks in strict
OUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | CC_BASH_ALLOWLIST_QUIET=1 CC_BASH_ALLOWLIST_STRICT=1 bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "quiet strict no stderr" "$OUT" "not matched"
assert_exit "quiet strict exit 2" "$RC" "2"

# Test 9: quiet alone is silent advisory
OUT=$(echo '{"tool_input":{"command":"git push origin main"}}' | CC_BASH_ALLOWLIST_QUIET=1 bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "quiet alone no stderr" "$OUT" "not matched"
assert_exit "quiet alone exit 0" "$RC" "0"

# Test 10: Bash(*) wildcard allows everything
cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(*)"] } }
EOF
OUT=$(echo '{"tool_input":{"command":"rm -rf /tmp/foo"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "wildcard allow no warning" "$OUT" "not matched"
assert_exit "wildcard allow exit 0" "$RC" "0"

# Test 11: empty allowlist — everything warns
cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{ "permissions": { "allow": [] } }
EOF
OUT=$(echo '{"tool_input":{"command":"echo hello"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "empty allowlist warns" "$OUT" "not matched"
assert_exit "empty allowlist advisory exit 0" "$RC" "0"

# Test 12: missing settings file — silent pass (no allowlist to compare against)
rm "$TMPDIR/.claude/settings.json"
OUT=$(echo '{"tool_input":{"command":"echo hello"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "missing settings still warns (no patterns)" "$OUT" "not matched"
assert_exit "missing settings exit 0" "$RC" "0"

# Test 13: local settings file is also read
cat > "$TMPDIR/.claude/settings.local.json" <<'EOF'
{ "permissions": { "allow": ["Bash(echo:*)"] } }
EOF
OUT=$(echo '{"tool_input":{"command":"echo hello"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_not_contains "local settings allow no warning" "$OUT" "not matched"
assert_exit "local settings exit 0" "$RC" "0"

# Test 14: non-Bash patterns (e.g. Read) are ignored
cat > "$TMPDIR/.claude/settings.json" <<'EOF'
{ "permissions": { "allow": ["Read(*)", "Edit(*)"] } }
EOF
rm -f "$TMPDIR/.claude/settings.local.json"
OUT=$(echo '{"tool_input":{"command":"git push"}}' | bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "non-Bash patterns ignored — git push warns" "$OUT" "not matched"
assert_exit "non-Bash patterns advisory exit 0" "$RC" "0"

# Restore HOME and clean up
export HOME="$HOME_BACKUP"
cd / && rm -rf "$TMPDIR"

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
[ "$FAIL" -eq 0 ]
