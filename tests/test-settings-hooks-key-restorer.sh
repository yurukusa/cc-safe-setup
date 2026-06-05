#!/bin/bash
# Tests for settings-hooks-key-restorer.sh
HOOK="$(dirname "$0")/../examples/settings-hooks-key-restorer.sh"
PASS=0 FAIL=0

# Each test uses a temporary CLAUDE_SETTINGS_FILE and a temporary HOME for backups.
setup_temp_env() {
  TMPDIR=$(mktemp -d)
  export TEST_HOME="$TMPDIR/home"
  mkdir -p "$TEST_HOME/.claude"
  export TEST_SETTINGS="$TEST_HOME/.claude/settings.json"
  export TEST_BACKUP_DIR="$TEST_HOME/.claude/settings-backups"
}

cleanup_temp_env() {
  rm -rf "$TMPDIR"
}

run_test() {
  local desc="$1" expected_exit="$2" expected_stderr_pattern="$3"
  local stderr_file
  stderr_file=$(mktemp)
  HOME="$TEST_HOME" CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" bash "$HOOK" >/dev/null 2>"$stderr_file"
  local actual_exit=$?
  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  local exit_ok=0
  local stderr_ok=0
  if [ "$actual_exit" -eq "$expected_exit" ]; then exit_ok=1; fi
  if [ -z "$expected_stderr_pattern" ]; then
    [ -z "$stderr_content" ] && stderr_ok=1
  else
    echo "$stderr_content" | grep -q "$expected_stderr_pattern" && stderr_ok=1
  fi

  if [ "$exit_ok" = "1" ] && [ "$stderr_ok" = "1" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (exit: got $actual_exit want $expected_exit; stderr pattern '$expected_stderr_pattern' match: $stderr_ok)"
    echo "    stderr was: $stderr_content"
    ((FAIL++))
  fi
}

echo "Testing settings-hooks-key-restorer.sh"
echo "======================================="

# Test 1: settings.json missing — silent exit 0
setup_temp_env
run_test "no settings.json: silent exit 0" 0 ""
cleanup_temp_env

# Test 2: settings.json present, no backups — silent exit 0
setup_temp_env
echo '{"permissions":{"allow":[]}}' > "$TEST_SETTINGS"
run_test "no backup dir: silent exit 0" 0 ""
cleanup_temp_env

# Test 3: settings.json has hooks, backup with same hooks — silent exit 0
setup_temp_env
echo '{"permissions":{"allow":[]},"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
cp "$TEST_SETTINGS" "$TEST_BACKUP_DIR/settings.json.latest"
run_test "hooks present, matching backup: silent exit 0" 0 ""
cleanup_temp_env

# Test 4: settings.json missing hooks key, backup HAS hooks — warn with restore command
setup_temp_env
echo '{"permissions":{"allow":["Bash(echo hello)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"permissions":{"allow":[]},"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "hooks lost from settings, backup has hooks: warn with restore" 0 "SILENT HOOKS LOSS DETECTED"
cleanup_temp_env

# Test 5: settings.json missing hooks, backup also missing hooks — silent exit 0 (user never had hooks)
setup_temp_env
echo '{"permissions":{"allow":[]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"permissions":{"allow":[]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "no hooks ever: silent exit 0" 0 ""
cleanup_temp_env

# Test 6: settings.json has hooks but count is 0 — emptied warning
setup_temp_env
echo '{"permissions":{"allow":[]},"hooks":{}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"permissions":{"allow":[]},"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "hooks key present but empty: warn but exit 0" 0 "hooks' key but it is empty"
cleanup_temp_env

# Test 7: settings.json missing hooks, only baseline backup has hooks
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"permissions":{"allow":[]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
echo '{"permissions":{"allow":[]},"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.baseline"
run_test "hooks lost, only baseline backup has hooks: warn" 0 "SILENT HOOKS LOSS DETECTED"
cleanup_temp_env

# Test 8: settings.json with hooks, both backups also have hooks — silent exit 0
setup_temp_env
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
cp "$TEST_SETTINGS" "$TEST_BACKUP_DIR/settings.json.latest"
cp "$TEST_SETTINGS" "$TEST_BACKUP_DIR/settings.json.baseline"
run_test "hooks present everywhere: silent exit 0" 0 ""
cleanup_temp_env

# Test 9: malformed settings.json — silent exit 0 (jq fails gracefully)
setup_temp_env
echo 'not valid json' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "malformed settings.json: no crash" 0 ""
cleanup_temp_env

# Test 10: backup file exists but malformed — silent exit 0
setup_temp_env
echo '{"permissions":{"allow":[]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo 'not valid' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "malformed backup: no crash" 0 ""
cleanup_temp_env

# Test 11: settings.json with hooks but tracks multiple types (PreToolUse + Stop)
setup_temp_env
cat > "$TEST_SETTINGS" <<'EOF'
{
  "permissions":{"allow":[]},
  "hooks":{
    "PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}],
    "Stop":[{"hooks":[{"type":"command","command":"b"}]}]
  }
}
EOF
mkdir -p "$TEST_BACKUP_DIR"
cp "$TEST_SETTINGS" "$TEST_BACKUP_DIR/settings.json.latest"
run_test "multiple hook types preserved: silent exit 0" 0 ""
cleanup_temp_env

# Test 12: settings.json with hooks key but the key is null
setup_temp_env
echo '{"permissions":{"allow":[]},"hooks":null}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "hooks key is null: warn it is empty" 0 "key but it is empty"
cleanup_temp_env

# Test 13: warn message contains the issue URL reference
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "warn message includes issue reference for context" 0 "issue #59870\|#59870"
cleanup_temp_env

# Test 14: warn message includes the restoration jq command
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
run_test "warn message includes jq restoration command" 0 "jq -s"
cleanup_temp_env

# Test 15: warn includes hook count from the prior backup
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
cat > "$TEST_BACKUP_DIR/settings.json.latest" <<'EOF'
{
  "hooks":{
    "PreToolUse":[{"hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}],
    "Stop":[{"hooks":[{"type":"command","command":"c"}]}]
  }
}
EOF
run_test "warn includes hook count (3)" 0 "had 3 hook"
cleanup_temp_env

# Test 16: latest backup missing hooks but baseline has hooks — uses baseline
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"permissions":{"allow":[]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.baseline"
run_test "fallback to baseline when latest has no hooks" 0 "settings.json.baseline"
cleanup_temp_env

# Test 17: latest backup has hooks but baseline does not — uses latest
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
echo '{"permissions":{"allow":[]}}' > "$TEST_BACKUP_DIR/settings.json.baseline"
run_test "uses latest when latest has hooks" 0 "settings.json.latest"
cleanup_temp_env

# Test 18: no auto-restore — hook does NOT modify settings.json
setup_temp_env
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
EXPECTED_CONTENT=$(cat "$TEST_SETTINGS")
HOME="$TEST_HOME" CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" bash "$HOOK" >/dev/null 2>/dev/null
ACTUAL_CONTENT=$(cat "$TEST_SETTINGS")
if [ "$EXPECTED_CONTENT" = "$ACTUAL_CONTENT" ]; then
  echo "  PASS: hook does NOT auto-modify settings.json"
  ((PASS++))
else
  echo "  FAIL: hook modified settings.json (should be read-only)"
  ((FAIL++))
fi
cleanup_temp_env

# Test 19: env override CLAUDE_SETTINGS_FILE is respected
setup_temp_env
CUSTOM_SETTINGS="$TMPDIR/custom-settings.json"
echo '{"permissions":{"allow":["Bash(test)"]}}' > "$CUSTOM_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_BACKUP_DIR/settings.json.latest"
# Don't write to TEST_SETTINGS — only CUSTOM_SETTINGS
stderr_file=$(mktemp)
HOME="$TEST_HOME" CLAUDE_SETTINGS_FILE="$CUSTOM_SETTINGS" bash "$HOOK" >/dev/null 2>"$stderr_file"
if grep -q "SILENT HOOKS LOSS DETECTED" "$stderr_file"; then
  echo "  PASS: CLAUDE_SETTINGS_FILE env override is respected"
  ((PASS++))
else
  echo "  FAIL: CLAUDE_SETTINGS_FILE env override did not work"
  ((FAIL++))
fi
rm -f "$stderr_file"
cleanup_temp_env

# Test 20: hook is read-only when hooks is present (no log output to stderr unless warning)
setup_temp_env
echo '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}]}}' > "$TEST_SETTINGS"
mkdir -p "$TEST_BACKUP_DIR"
cp "$TEST_SETTINGS" "$TEST_BACKUP_DIR/settings.json.latest"
stderr_file=$(mktemp)
HOME="$TEST_HOME" CLAUDE_SETTINGS_FILE="$TEST_SETTINGS" bash "$HOOK" >/dev/null 2>"$stderr_file"
if [ -s "$stderr_file" ]; then
  echo "  FAIL: hook emitted output when none was expected"
  cat "$stderr_file"
  ((FAIL++))
else
  echo "  PASS: hook is silent when hooks key is present"
  ((PASS++))
fi
rm -f "$stderr_file"
cleanup_temp_env

echo ""
echo "Total: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
