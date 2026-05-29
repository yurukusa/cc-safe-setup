#!/bin/bash
# Tests for compound-bash-permission-resolver.sh (Cluster 6 Axis 1)
# Covers: compound detection, per-component matching, all-covered vs
# partial-coverage advisories, fail-open, environment-variable behavior,
# edge cases (env prefixes, path binaries, single-pipe vs ||, etc.).

HOOK="examples/compound-bash-permission-resolver.sh"
PASS=0 FAIL=0

# Override HOME so test settings are read in isolation.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.claude"

write_settings() {
    # $1 = JSON array body for permissions.allow
    cat > "$TEST_HOME/.claude/settings.json" <<EOF
{"permissions":{"allow":$1}}
EOF
}

clear_settings() {
    rm -f "$TEST_HOME/.claude/settings.json"
    rm -f "$TEST_HOME/.claude/settings.local.json"
}

run_hook() {
    local payload="$1"; shift
    HOME="$TEST_HOME" env "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  got: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# ---- Group 1: non-compound commands → no advisory ----

# Test 1: bare command, no compound separator → no advisory
write_settings '["Bash(git status:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"git status"}}')
RC=$?
assert_exit "bare command exit 0" "$RC" "0"
assert_not_contains "bare command no advisory" "$OUT" "compound-bash-permission-resolver"

# Test 2: bare command with flags → no advisory
OUT=$(run_hook '{"tool_input":{"command":"git status --short"}}')
RC=$?
assert_exit "bare flags exit 0" "$RC" "0"
assert_not_contains "bare flags no advisory" "$OUT" "compound-bash-permission-resolver"

# Test 3: empty input fails open
OUT=$(run_hook '{}')
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
assert_not_contains "empty input no advisory" "$OUT" "compound-bash-permission-resolver"

# Test 4: invalid JSON fails open
OUT=$(run_hook 'not json')
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# ---- Group 2: no patterns configured → no advisory ----

# Test 5: compound bash but no Bash() rules in any settings → silent
clear_settings
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
RC=$?
assert_exit "no patterns exit 0" "$RC" "0"
assert_not_contains "no patterns no advisory" "$OUT" "compound-bash-permission-resolver"

# Test 6: non-Bash rules don't trigger evaluation
write_settings '["Read(*)","Edit(*.ts)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
RC=$?
assert_exit "non-Bash patterns exit 0" "$RC" "0"
assert_not_contains "non-Bash patterns no advisory" "$OUT" "compound-bash-permission-resolver"

# ---- Group 3: all components covered → safe-to-approve advisory ----

# Test 7: && with both segments matching binary-level patterns
write_settings '["Bash(cd:*)","Bash(git:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
RC=$?
assert_exit "all-covered && exit 0" "$RC" "0"
assert_contains "all-covered && heading" "$OUT" "Compound bash detected"
assert_contains "all-covered && count" "$OUT" "2 components"
assert_contains "all-covered && safe" "$OUT" "Safe to approve"
assert_contains "all-covered && cites Axis 1" "$OUT" "Axis 1"

# Test 8: subcommand-level patterns recognized
write_settings '["Bash(cd:*)","Bash(git status:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
assert_contains "subcommand pattern recognized" "$OUT" "Safe to approve"

# Test 9: || separator
write_settings '["Bash(test:*)","Bash(echo:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"test -f x || echo missing"}}')
RC=$?
assert_exit "|| exit 0" "$RC" "0"
assert_contains "|| triggers" "$OUT" "Compound bash detected"
assert_contains "|| count" "$OUT" "2 components"

# Test 10: ; separator
write_settings '["Bash(echo:*)","Bash(ls:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"echo start; ls"}}')
RC=$?
assert_exit "; exit 0" "$RC" "0"
assert_contains "; triggers" "$OUT" "Compound bash detected"
assert_contains "; count" "$OUT" "2 components"

# Test 11: single pipe |
write_settings '["Bash(cat:*)","Bash(grep:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cat /etc/hosts | grep localhost"}}')
RC=$?
assert_exit "| exit 0" "$RC" "0"
assert_contains "| triggers" "$OUT" "Compound bash detected"
assert_contains "| count" "$OUT" "2 components"

# Test 12: three-way compound
write_settings '["Bash(cd:*)","Bash(git:*)","Bash(ls:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status && ls"}}')
RC=$?
assert_exit "3-way exit 0" "$RC" "0"
assert_contains "3-way count" "$OUT" "3 components"
assert_contains "3-way safe" "$OUT" "Safe to approve"

# ---- Group 4: partial coverage → uncovered-list advisory ----

# Test 13: one component covered, one not
write_settings '["Bash(cd:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
RC=$?
assert_exit "partial exit 0" "$RC" "0"
assert_contains "partial coverage line" "$OUT" "Coverage: 1 of 2"
assert_contains "partial names uncovered binary" "$OUT" "Uncovered components"
assert_contains "partial uncovered is git" "$OUT" "git"
assert_not_contains "partial does not say safe" "$OUT" "Safe to approve"

# Test 14: none covered (yet compound) → still emits partial-coverage shape
write_settings '["Bash(npm:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
RC=$?
assert_exit "none-of-many exit 0" "$RC" "0"
assert_contains "none covered line" "$OUT" "Coverage: 0 of 2"
assert_contains "none uncovered list" "$OUT" "cd git"

# ---- Group 5: env-var prefix handling ----

# Test 15: env var prefix stripped on segment
write_settings '["Bash(cd:*)","Bash(python:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd src && DEBUG=1 python app.py"}}')
RC=$?
assert_exit "env prefix exit 0" "$RC" "0"
assert_contains "env prefix matches python" "$OUT" "Safe to approve"

# Test 16: multiple env vars stripped
write_settings '["Bash(python:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"DEBUG=1 PYTHONPATH=src python app.py | head"}}')
RC=$?
assert_contains "multi-env recognized" "$OUT" "Compound bash detected"
# python covered, head not.
assert_contains "multi-env partial" "$OUT" "Coverage: 1 of 2"
assert_contains "multi-env uncovered head" "$OUT" "head"

# ---- Group 6: path-prefixed binary ----

# Test 17: /usr/bin/git normalizes to git
write_settings '["Bash(git:*)","Bash(cd:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && /usr/bin/git status"}}')
RC=$?
assert_contains "path binary matches" "$OUT" "Safe to approve"

# ---- Group 7: settings location merging ----

# Test 18: project-level settings.local.json merges with home settings.json
clear_settings
write_settings '["Bash(cd:*)"]'
PROJ_DIR=$(mktemp -d)
mkdir -p "$PROJ_DIR/.claude"
cat > "$PROJ_DIR/.claude/settings.local.json" <<'EOF'
{"permissions":{"allow":["Bash(git:*)"]}}
EOF
OUT=$( cd "$PROJ_DIR" && HOME="$TEST_HOME" bash "$OLDPWD/$HOOK" <<< '{"tool_input":{"command":"cd repo && git status"}}' 2>&1 )
RC=$?
rm -rf "$PROJ_DIR"
assert_exit "merge exit 0" "$RC" "0"
assert_contains "merge across files" "$OUT" "Safe to approve"

# ---- Group 8: environment variables on the hook itself ----

# Test 19: CC_COMPOUND_RESOLVER_DISABLE=1 silences advisory
write_settings '["Bash(cd:*)","Bash(git:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}' CC_COMPOUND_RESOLVER_DISABLE=1)
RC=$?
assert_exit "disabled exit 0" "$RC" "0"
assert_not_contains "disabled no advisory" "$OUT" "compound-bash-permission-resolver"

# Test 20: CC_COMPOUND_RESOLVER_VERBOSE=1 adds breakdown line
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}' CC_COMPOUND_RESOLVER_VERBOSE=1)
RC=$?
assert_contains "verbose includes breakdown" "$OUT" "resolver breakdown"
assert_contains "verbose includes total" "$OUT" "total=2"
assert_contains "verbose includes covered" "$OUT" "covered=2"
assert_exit "verbose exit 0" "$RC" "0"

# ---- Group 9: separator edge cases ----

# Test 21: || not split as single |
write_settings '["Bash(test:*)","Bash(echo:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"test -f x || echo missing"}}')
assert_contains "|| count 2" "$OUT" "2 components"
assert_not_contains "|| not 3 components" "$OUT" "3 components"

# Test 22: && not split as ; or |
OUT=$(run_hook '{"tool_input":{"command":"echo a && echo b"}}')
write_settings '["Bash(echo:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"echo a && echo b"}}')
assert_contains "&& only 2 segments" "$OUT" "2 components"

# Test 23: single segment in compound shape (trailing &&) doesn't crash
OUT=$(run_hook '{"tool_input":{"command":"git status &&"}}')
RC=$?
assert_exit "trailing && exit 0" "$RC" "0"

# Test 24: leading separator handled
OUT=$(run_hook '{"tool_input":{"command":"&& git status"}}')
RC=$?
assert_exit "leading && exit 0" "$RC" "0"

# ---- Group 10: noise resilience ----

# Test 25: command with no separator does not trigger
write_settings '["Bash(git:*)"]'
OUT=$(run_hook '{"tool_input":{"command":"git commit -m \"fix && bug\""}}')
RC=$?
# NOTE: this is a known false positive — quoted && inside arguments is
# treated as a separator. The advisory will fire. We assert it does not
# CRASH and exits 0. The advisory just becomes a no-op information.
assert_exit "quoted && exit 0" "$RC" "0"

# Test 26: very long command does not crash
LONG=$(printf 'echo a && %.0s' {1..50})
LONG="${LONG}true"
OUT=$(run_hook "$(jq -n --arg c "$LONG" '{tool_input:{command:$c}}')")
RC=$?
assert_exit "long command exit 0" "$RC" "0"

# Test 27: malformed settings file does not crash hook
write_settings '["Bash(git:*)"]'
echo '{ not valid json' > "$TEST_HOME/.claude/settings.local.json"
OUT=$(run_hook '{"tool_input":{"command":"cd repo && git status"}}')
RC=$?
assert_exit "bad settings exit 0" "$RC" "0"
rm -f "$TEST_HOME/.claude/settings.local.json"

# Test 28: missing tool_input.command field
OUT=$(run_hook '{"tool_input":{}}')
RC=$?
assert_exit "missing command exit 0" "$RC" "0"
assert_not_contains "missing command no advisory" "$OUT" "compound-bash-permission-resolver"

echo ""
echo "Tests: $((PASS+FAIL)) | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
