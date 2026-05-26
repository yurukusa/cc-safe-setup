#!/bin/bash
# Tests for always-allow-pattern-suggester.sh (Cluster 6 Axis 2)
# Covers: pattern suggestion shape, existing-rule suppression, fail-open,
# environment-variable behavior, edge cases.

HOOK="examples/always-allow-pattern-suggester.sh"
PASS=0 FAIL=0

# Override HOME so local user settings don't suppress test suggestions.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.claude"

run_hook() {
    # $1 = JSON payload, optional extra env vars trail as $2..$n
    local payload="$1"; shift
    HOME="$TEST_HOME" env "$@" bash "$HOOK" <<< "$payload" 2>&1
}

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

# Test 1: command with subcommand suggests "binary subcommand:*" pattern
OUT=$(run_hook '{"tool_input":{"command":"git commit -m \"fix typo\""}}')
RC=$?
assert_contains "subcommand suggestion shape" "$OUT" 'Bash(git commit:\*)'
assert_contains "subcommand advisory has heading" "$OUT" "always-allow-pattern-suggester"
assert_exit "subcommand exit 0" "$RC" "0"

# Test 2: bare binary suggests "binary:*" pattern
OUT=$(run_hook '{"tool_input":{"command":"ls"}}')
RC=$?
assert_contains "bare bin suggestion shape" "$OUT" 'Bash(ls:\*)'
assert_exit "bare bin exit 0" "$RC" "0"

# Test 3: binary with flag first (no subcommand) suggests "binary:*"
OUT=$(run_hook '{"tool_input":{"command":"npm --version"}}')
RC=$?
assert_contains "flag-first suggests binary:*" "$OUT" 'Bash(npm:\*)'
assert_not_contains "flag-first does not include --version in pattern" "$OUT" 'npm --version:'
assert_exit "flag-first exit 0" "$RC" "0"

# Test 4: path-prefixed binary normalizes to basename
# (Filename arg like test.py has a "." so it's not classified as a subcommand;
# the suggester falls back to the binary-level pattern, which is the desired
# behavior — wildcards live at the binary level, not the filename level.)
OUT=$(run_hook '{"tool_input":{"command":"/usr/local/bin/python test.py"}}')
RC=$?
assert_contains "path binary normalized" "$OUT" 'Bash(python:\*)'
assert_not_contains "path binary not raw" "$OUT" '/usr/local/bin/python'
assert_exit "path binary exit 0" "$RC" "0"

# Test 5: env var prefix is stripped (one or more env vars)
OUT=$(run_hook '{"tool_input":{"command":"DEBUG=1 PYTHONPATH=src python script.py"}}')
RC=$?
assert_contains "env prefix stripped" "$OUT" 'Bash(python:\*)'
assert_not_contains "env not in pattern" "$OUT" 'DEBUG'
assert_not_contains "env PYTHONPATH stripped" "$OUT" 'PYTHONPATH'
assert_exit "env prefix exit 0" "$RC" "0"

# Test 6: compound bash uses first segment
OUT=$(run_hook '{"tool_input":{"command":"git status && git commit -m x"}}')
RC=$?
assert_contains "compound uses first segment" "$OUT" 'Bash(git status:\*)'
assert_not_contains "compound ignores second segment" "$OUT" 'git commit:'
assert_exit "compound exit 0" "$RC" "0"

# Test 7: empty input fails open
OUT=$(run_hook '{}')
RC=$?
assert_exit "empty input exit 0" "$RC" "0"
assert_not_contains "empty input no advisory" "$OUT" "always-allow-pattern-suggester"

# Test 8: invalid JSON fails open
OUT=$(run_hook 'not json')
RC=$?
assert_exit "invalid JSON exit 0" "$RC" "0"

# Test 9: CC_PATTERN_SUGGESTER_DISABLE=1 silences advisory
OUT=$(run_hook '{"tool_input":{"command":"git commit -m \"x\""}}' CC_PATTERN_SUGGESTER_DISABLE=1)
RC=$?
assert_exit "disabled exit 0" "$RC" "0"
assert_not_contains "disabled no advisory" "$OUT" "always-allow-pattern-suggester"
assert_not_contains "disabled no Bash() suggestion" "$OUT" 'Bash(git'

# Test 10: CC_PATTERN_SUGGESTER_VERBOSE=1 adds breakdown line
OUT=$(run_hook '{"tool_input":{"command":"git status"}}' CC_PATTERN_SUGGESTER_VERBOSE=1)
RC=$?
assert_contains "verbose includes breakdown" "$OUT" "suggester breakdown"
assert_contains "verbose includes binary" "$OUT" "binary=git"
assert_exit "verbose exit 0" "$RC" "0"

# Test 11: existing pattern in user settings suppresses advisory
cat > "$TEST_HOME/.claude/settings.json" <<'EOF'
{"permissions":{"allow":["Bash(git status:*)"]}}
EOF
OUT=$(run_hook '{"tool_input":{"command":"git status"}}')
RC=$?
assert_exit "existing pattern exit 0" "$RC" "0"
assert_not_contains "existing pattern no advisory" "$OUT" "always-allow-pattern-suggester"

# Test 12: different pattern in user settings still emits advisory
cat > "$TEST_HOME/.claude/settings.json" <<'EOF'
{"permissions":{"allow":["Bash(npm:*)"]}}
EOF
OUT=$(run_hook '{"tool_input":{"command":"git diff"}}')
RC=$?
assert_contains "different pattern still suggests" "$OUT" 'Bash(git diff:\*)'
assert_exit "different pattern exit 0" "$RC" "0"

# Clean up settings.json for subsequent tests.
rm -f "$TEST_HOME/.claude/settings.json"

# Test 13: docker container ls pattern preserved
OUT=$(run_hook '{"tool_input":{"command":"docker container ls"}}')
RC=$?
assert_contains "docker subcommand suggestion" "$OUT" 'Bash(docker container:\*)'
assert_exit "docker subcommand exit 0" "$RC" "0"

# Test 14: curl with flags suggests binary level only
OUT=$(run_hook '{"tool_input":{"command":"curl -sI https://example.com"}}')
RC=$?
assert_contains "curl with flags suggests binary" "$OUT" 'Bash(curl:\*)'
assert_exit "curl with flags exit 0" "$RC" "0"

# Test 15: numeric-leading first arg is treated as non-subcommand
OUT=$(run_hook '{"tool_input":{"command":"sleep 5"}}')
RC=$?
assert_contains "numeric arg falls back to binary" "$OUT" 'Bash(sleep:\*)'
assert_not_contains "numeric arg not in pattern" "$OUT" 'sleep 5:'
assert_exit "numeric arg exit 0" "$RC" "0"

# Test 16: pipe-only command takes first segment (path arg / is not a subcommand)
OUT=$(run_hook '{"tool_input":{"command":"cat /etc/hosts | grep localhost"}}')
RC=$?
assert_contains "pipe takes first segment" "$OUT" 'Bash(cat:\*)'
assert_not_contains "pipe ignores piped second" "$OUT" 'grep localhost'
assert_exit "pipe exit 0" "$RC" "0"

# Test 17: advisory mentions settings.local.json target file
OUT=$(run_hook '{"tool_input":{"command":"npm test"}}')
assert_contains "advisory names target settings file" "$OUT" "settings.local.json"

echo ""
echo "Tests: $((PASS+FAIL)) | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
