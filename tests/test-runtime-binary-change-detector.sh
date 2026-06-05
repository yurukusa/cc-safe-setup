#!/bin/bash
# Tests for runtime-binary-change-detector.sh
HOOK="$(dirname "$0")/../examples/runtime-binary-change-detector.sh"
PASS=0 FAIL=0

TESTROOT=$(mktemp -d)
trap "rm -rf '$TESTROOT'" EXIT

# Build a fake `claude` binary so the hook has something to fingerprint.
FAKE_BIN_DIR="$TESTROOT/bin"
mkdir -p "$FAKE_BIN_DIR"
FAKE_BIN="$FAKE_BIN_DIR/claude"
cat > "$FAKE_BIN" <<'EOF'
#!/bin/bash
case "$1" in
  --version) echo "${FAKE_CLAUDE_VERSION:-1.2.3 (Claude Code)}" ;;
  *) echo "fake claude" ;;
esac
EOF
chmod +x "$FAKE_BIN"

# Helper: invoke the hook with a fresh HOME and the fake binary on PATH.
run_hook() {
  local home_dir="$1" event_json="$2"
  shift 2
  HOME="$home_dir" PATH="$FAKE_BIN_DIR:$PATH" \
    env "$@" bash "$HOOK" <<< "$event_json"
}

# Helper: capture stderr only (the hook's warnings go there).
run_hook_stderr() {
  local home_dir="$1" event_json="$2"
  shift 2
  HOME="$home_dir" PATH="$FAKE_BIN_DIR:$PATH" \
    env "$@" bash "$HOOK" <<< "$event_json" 2>&1 >/dev/null
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        expected: $expected"
    echo "        actual:   $actual"
    FAIL=$((FAIL+1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf "%s" "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        needle:   $needle"
    echo "        haystack: $haystack"
    FAIL=$((FAIL+1))
  fi
}

assert_empty() {
  local desc="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        expected empty, got: $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "Testing runtime-binary-change-detector.sh"
echo "========================================="

# Each test uses a fresh HOME so the state file starts clean.

# 1. First session on session_start: creates state, no warning.
HOME1=$(mktemp -d -p "$TESTROOT")
out1=$(run_hook_stderr "$HOME1" '{"event":"session_start"}')
exit1=$?
assert_eq "first run exits 0" "0" "$exit1"
assert_empty "first run prints no warning" "$out1"
if [ -f "$HOME1/.claude/runtime-binary-state.txt" ]; then
  echo "  PASS: first run created state file"
  PASS=$((PASS+1))
else
  echo "  FAIL: first run did not create state file"
  FAIL=$((FAIL+1))
fi

# 2. Identical second session: no warning.
out2=$(run_hook_stderr "$HOME1" '{"event":"session_start"}')
exit2=$?
assert_eq "identical session exits 0" "0" "$exit2"
assert_empty "identical session prints no warning" "$out2"

# 3. Version changed: warning printed.
HOME3=$(mktemp -d -p "$TESTROOT")
run_hook "$HOME3" '{"event":"session_start"}' >/dev/null 2>&1
# Now force the fake binary to return a different version.
out3=$(run_hook_stderr "$HOME3" '{"event":"session_start"}' \
  FAKE_CLAUDE_VERSION="2.0.0 (Claude Code)")
exit3=$?
assert_eq "version change exits 0" "0" "$exit3"
assert_contains "version change warns" "binary changed" "$out3"
assert_contains "version change shows old→new" "→" "$out3"
assert_contains "version change cites release notes URL" \
  "github.com/anthropics/claude-code/releases" "$out3"

# 4. State file gets updated after the warning so the next session is silent.
out4=$(run_hook_stderr "$HOME3" '{"event":"session_start"}' \
  FAKE_CLAUDE_VERSION="2.0.0 (Claude Code)")
assert_empty "second session after change is silent again" "$out4"

# 5. Size/mtime change (same version string) is also caught.
HOME5=$(mktemp -d -p "$TESTROOT")
run_hook "$HOME5" '{"event":"session_start"}' >/dev/null 2>&1
# Touch the binary to bump mtime.
sleep 1
touch "$FAKE_BIN"
out5=$(run_hook_stderr "$HOME5" '{"event":"session_start"}')
assert_contains "mtime-only change warns" "binary changed" "$out5"
assert_contains "mtime-only change cites size/mtime path" "Path:" "$out5"

# 6. CC_BINARY_DETECTOR_SILENT=1 suppresses the warning.
HOME6=$(mktemp -d -p "$TESTROOT")
run_hook "$HOME6" '{"event":"session_start"}' >/dev/null 2>&1
out6=$(run_hook_stderr "$HOME6" '{"event":"session_start"}' \
  FAKE_CLAUDE_VERSION="3.0.0 (Claude Code)" \
  CC_BINARY_DETECTOR_SILENT="1")
assert_empty "silent mode suppresses warning on version change" "$out6"
# State should still update so subsequent non-silent sessions don't double-warn.
out6b=$(run_hook_stderr "$HOME6" '{"event":"session_start"}' \
  FAKE_CLAUDE_VERSION="3.0.0 (Claude Code)")
assert_empty "silent mode still updates state (next session quiet)" "$out6b"

# 7. Non-session_start event: hook returns 0 with no work.
HOME7=$(mktemp -d -p "$TESTROOT")
out7=$(run_hook_stderr "$HOME7" '{"event":"pre_tool_use","tool_name":"Bash"}')
exit7=$?
assert_eq "non-session event exits 0" "0" "$exit7"
assert_empty "non-session event prints no warning" "$out7"
if [ -f "$HOME7/.claude/runtime-binary-state.txt" ]; then
  echo "  FAIL: non-session event should not create state file"
  FAIL=$((FAIL+1))
else
  echo "  PASS: non-session event skipped state write"
  PASS=$((PASS+1))
fi

# 8. PascalCase event name (SessionStart) is also accepted.
HOME8=$(mktemp -d -p "$TESTROOT")
out8=$(run_hook_stderr "$HOME8" '{"event":"SessionStart"}')
exit8=$?
assert_eq "PascalCase SessionStart exits 0" "0" "$exit8"
if [ -f "$HOME8/.claude/runtime-binary-state.txt" ]; then
  echo "  PASS: PascalCase SessionStart created state file"
  PASS=$((PASS+1))
else
  echo "  FAIL: PascalCase SessionStart did not create state file"
  FAIL=$((FAIL+1))
fi

# 9. hook_event_name as a fallback field.
HOME9=$(mktemp -d -p "$TESTROOT")
out9=$(run_hook_stderr "$HOME9" '{"hook_event_name":"SessionStart"}')
exit9=$?
assert_eq "hook_event_name fallback exits 0" "0" "$exit9"
if [ -f "$HOME9/.claude/runtime-binary-state.txt" ]; then
  echo "  PASS: hook_event_name fallback created state file"
  PASS=$((PASS+1))
else
  echo "  FAIL: hook_event_name fallback did not create state file"
  FAIL=$((FAIL+1))
fi

# 10. Missing claude binary: hook exits 0 silently.
# PATH gets a dummy bin dir with no claude. Standard system bins (bash, etc.)
# must remain reachable, so we prepend the empty dir to the existing PATH
# instead of replacing it wholesale.
HOME10=$(mktemp -d -p "$TESTROOT")
EMPTY_BIN="$TESTROOT/empty"
mkdir -p "$EMPTY_BIN"
out10=$(HOME="$HOME10" PATH="$EMPTY_BIN:/usr/bin:/bin" bash "$HOOK" \
  <<< '{"event":"session_start"}' 2>&1 >/dev/null)
exit10=$?
assert_eq "missing claude exits 0" "0" "$exit10"
assert_empty "missing claude prints nothing" "$out10"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
