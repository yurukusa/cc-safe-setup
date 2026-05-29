#!/bin/bash
# Tests for claude-code-version-pin-advisor.sh
HOOK="$(dirname "$0")/../examples/claude-code-version-pin-advisor.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# Provide a fake claude binary via CC_VERSION_PIN_ADVISOR_CLAUDE_BIN for tests
# that exercise the binary-detection path. Most tests use CLAUDE_CODE_VERSION
# directly which is faster and deterministic.

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

# Fake claude binary that prints a fixed version
FAKE_CLAUDE="$TMPDIR_RUN/fake-claude"
cat > "$FAKE_CLAUDE" <<'EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
  echo "2.1.156 (Claude Code)"
fi
EOF
chmod +x "$FAKE_CLAUDE"

# Fake claude binary that returns malformed output
MALFORMED_CLAUDE="$TMPDIR_RUN/malformed-claude"
cat > "$MALFORMED_CLAUDE" <<'EOF'
#!/bin/bash
echo "Claude Code - latest"
EOF
chmod +x "$MALFORMED_CLAUDE"

# Fake claude binary that returns nothing
SILENT_CLAUDE="$TMPDIR_RUN/silent-claude"
cat > "$SILENT_CLAUDE" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$SILENT_CLAUDE"

echo "Testing claude-code-version-pin-advisor.sh"
echo "==========================================="

# Test 1: version below threshold (2.1.153) → silent exit 0
OUT=$(CLAUDE_CODE_VERSION=2.1.153 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "version 2.1.153 (below threshold) → silent exit 0" pass
else
  run_test "version 2.1.153 → silent (exit=$EXIT, out=$OUT)" fail
fi

# Test 2: version at threshold (2.1.154) → advisory printed
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ADVISORY"; then
  run_test "version 2.1.154 (at threshold) → advisory printed" pass
else
  run_test "version 2.1.154 → advisory (exit=$EXIT, out=$OUT)" fail
fi

# Test 3: version above threshold (2.1.156) → advisory printed
OUT=$(CLAUDE_CODE_VERSION=2.1.156 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && echo "$OUT" | grep -q "ADVISORY" && echo "$OUT" | grep -q "2.1.156"; then
  run_test "version 2.1.156 (above threshold) → advisory mentions actual version" pass
else
  run_test "version 2.1.156 → advisory (exit=$EXIT, out=$OUT)" fail
fi

# Test 4: version far above threshold (2.2.0) → advisory printed
OUT=$(CLAUDE_CODE_VERSION=2.2.0 bash "$HOOK" 2>&1)
if [ -n "$(echo "$OUT" | grep ADVISORY)" ]; then
  run_test "version 2.2.0 (major.minor jump) → advisory" pass
else
  run_test "version 2.2.0 → advisory (got: $OUT)" fail
fi

# Test 5: version 2.1.100 (well below) → silent
OUT=$(CLAUDE_CODE_VERSION=2.1.100 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "version 2.1.100 (well below threshold) → silent" pass
else
  run_test "version 2.1.100 → silent (exit=$EXIT, out=$OUT)" fail
fi

# Test 6: DISABLE=1 silences regardless of version
OUT=$(CLAUDE_CODE_VERSION=2.1.156 CC_VERSION_PIN_ADVISOR_DISABLE=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "DISABLE=1 silences even when version triggers advisory" pass
else
  run_test "DISABLE=1 silences (exit=$EXIT, out=$OUT)" fail
fi

# Test 7: QUIET=1 silences regardless of version
OUT=$(CLAUDE_CODE_VERSION=2.1.156 CC_VERSION_PIN_ADVISOR_QUIET=1 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "QUIET=1 silences even when version triggers advisory" pass
else
  run_test "QUIET=1 silences (exit=$EXIT, out=$OUT)" fail
fi

# Test 8: custom THRESHOLD override (2.1.150 lower threshold)
OUT=$(CLAUDE_CODE_VERSION=2.1.151 CC_VERSION_PIN_ADVISOR_THRESHOLD=2.1.150 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "ADVISORY"; then
  run_test "custom THRESHOLD=2.1.150 triggers for 2.1.151" pass
else
  run_test "custom THRESHOLD=2.1.150 for 2.1.151 (got: $OUT)" fail
fi

# Test 9: custom THRESHOLD override (2.1.200 higher threshold)
OUT=$(CLAUDE_CODE_VERSION=2.1.156 CC_VERSION_PIN_ADVISOR_THRESHOLD=2.1.200 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "custom THRESHOLD=2.1.200 silences for 2.1.156" pass
else
  run_test "custom THRESHOLD=2.1.200 silences (exit=$EXIT, out=$OUT)" fail
fi

# Test 10: claude binary not found → fail-open silent
# PATH with only /bin and /usr/bin (no claude installed there) means
# command -v claude returns nothing. We need /bin and /usr/bin so that
# env -i can find bash itself.
OUT=$(env -i HOME="$HOME" PATH="$TMPDIR_RUN/empty-bin:/bin:/usr/bin" bash "$HOOK" 2>&1)
EXIT=$?
# In test environments where claude IS in /usr/bin or /bin, this test may
# not be deterministic. Use CC_VERSION_PIN_ADVISOR_CLAUDE_BIN pointing at
# a nonexistent file as the deterministic path.
OUT=$(env -i HOME="$HOME" PATH="/bin:/usr/bin" \
  CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$TMPDIR_RUN/does-not-exist" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "claude binary not found → fail-open silent" pass
else
  run_test "claude binary not found (exit=$EXIT, out=$OUT)" fail
fi

# Test 11: malformed version output → fail-open silent
OUT=$(CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$MALFORMED_CLAUDE" \
  env -i HOME="$HOME" PATH="/usr/bin:/bin" \
  CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$MALFORMED_CLAUDE" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "malformed version output → fail-open silent" pass
else
  run_test "malformed version output → fail-open (exit=$EXIT, out=$OUT)" fail
fi

# Test 12: silent claude binary (no version) → fail-open silent
OUT=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" \
  CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$SILENT_CLAUDE" \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "silent claude binary → fail-open silent" pass
else
  run_test "silent claude binary → fail-open (exit=$EXIT, out=$OUT)" fail
fi

# Test 13: detection via CC_VERSION_PIN_ADVISOR_CLAUDE_BIN (fake binary at 2.1.156)
OUT=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" \
  CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$FAKE_CLAUDE" \
  bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "2.1.156" && echo "$OUT" | grep -q "ADVISORY"; then
  run_test "fake claude binary at 2.1.156 → advisory mentions version" pass
else
  run_test "fake claude binary detection (got: $OUT)" fail
fi

# Test 14: CLAUDE_CODE_VERSION env var preferred over claude --version
# Even with binary at 2.1.156, env var at 2.1.153 should silence
OUT=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" \
  CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$FAKE_CLAUDE" \
  CLAUDE_CODE_VERSION=2.1.153 \
  bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "CLAUDE_CODE_VERSION env var preferred over binary detection" pass
else
  run_test "env var preferred (exit=$EXIT, out=$OUT)" fail
fi

# Test 15: advisory names sub-pattern 16A
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "16A" && echo "$OUT" | grep -q "Custom agents"; then
  run_test "advisory names sub-pattern 16A (custom agents)" pass
else
  run_test "advisory names 16A (got: $OUT)" fail
fi

# Test 16: advisory names sub-pattern 16B
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "16B" && echo "$OUT" | grep -q "Anthropic-compatible"; then
  run_test "advisory names sub-pattern 16B (Anthropic-compatible)" pass
else
  run_test "advisory names 16B (got: $OUT)" fail
fi

# Test 17: advisory names sub-pattern 16C
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "16C" && echo "$OUT" | grep -q "VS Code"; then
  run_test "advisory names sub-pattern 16C (VS Code)" pass
else
  run_test "advisory names 16C (got: $OUT)" fail
fi

# Test 18: advisory names sub-pattern 16D
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "16D" && echo "$OUT" | grep -q "context operations"; then
  run_test "advisory names sub-pattern 16D (context operations)" pass
else
  run_test "advisory names 16D (got: $OUT)" fail
fi

# Test 19: advisory includes pin command
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "npm install -g @anthropic-ai/claude-code@2.1.153"; then
  run_test "advisory includes pin command" pass
else
  run_test "advisory includes pin command (got: $OUT)" fail
fi

# Test 20: advisory includes auto-update suppression
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CLAUDE_CODE_DISABLE_AUTO_UPDATE=1"; then
  run_test "advisory includes auto-update suppression" pass
else
  run_test "advisory includes auto-update suppression (got: $OUT)" fail
fi

# Test 21: advisory references anchor issue #63469
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "63469"; then
  run_test "advisory references anchor issue #63469" pass
else
  run_test "advisory references #63469 (got: $OUT)" fail
fi

# Test 22: advisory references field guide Gist
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "05c120466996734f7bc2ad6d41fdedec"; then
  run_test "advisory references field guide Gist URL" pass
else
  run_test "advisory references Gist (got: $OUT)" fail
fi

# Test 23: advisory mentions QUIET silence path
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "CC_VERSION_PIN_ADVISOR_QUIET"; then
  run_test "advisory mentions QUIET env var to silence" pass
else
  run_test "advisory mentions QUIET (got: $OUT)" fail
fi

# Test 24: output written to stderr, stdout empty
STDOUT=$(CLAUDE_CODE_VERSION=2.1.156 bash "$HOOK" 2>/dev/null)
if [ -z "$STDOUT" ]; then
  run_test "warning written to stderr, stdout empty" pass
else
  run_test "warning to stderr (stdout was: $STDOUT)" fail
fi

# Test 25: ADVISORY prefix (not BLOCKED)
OUT=$(CLAUDE_CODE_VERSION=2.1.154 bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "^ADVISORY:"; then
  run_test "uses ADVISORY prefix (non-blocking)" pass
else
  run_test "uses ADVISORY prefix (got: $OUT)" fail
fi

# Test 26: malformed version (non-semver) → fail-open silent
OUT=$(CLAUDE_CODE_VERSION="latest" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "non-semver version 'latest' → fail-open silent" pass
else
  run_test "non-semver 'latest' (exit=$EXIT, out=$OUT)" fail
fi

# Test 27: empty version string → fail-open silent
# Empty env var means falling back to binary detection; use
# CC_VERSION_PIN_ADVISOR_CLAUDE_BIN pointing at nonexistent file to
# deterministically force binary detection to fail.
OUT=$(env -i HOME="$HOME" PATH="/bin:/usr/bin" \
  CC_VERSION_PIN_ADVISOR_CLAUDE_BIN="$TMPDIR_RUN/does-not-exist" \
  CLAUDE_CODE_VERSION="" bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "empty version + no claude binary → fail-open silent" pass
else
  run_test "empty version + no binary (exit=$EXIT, out=$OUT)" fail
fi

# Test 28: version with suffix tag (2.1.154-beta) → advisory (suffix stripped)
OUT=$(CLAUDE_CODE_VERSION="2.1.154-beta" bash "$HOOK" 2>&1)
if echo "$OUT" | grep -q "ADVISORY"; then
  run_test "version 2.1.154-beta (suffix stripped) → advisory" pass
else
  run_test "version 2.1.154-beta → advisory (got: $OUT)" fail
fi

# Test 29: stdin JSON consumed (SessionStart hooks receive JSON)
OUT=$(echo '{"hook_event_name":"SessionStart"}' | \
  CLAUDE_CODE_VERSION=2.1.153 bash "$HOOK" 2>&1)
EXIT=$?
if [ "$EXIT" = "0" ] && [ -z "$OUT" ]; then
  run_test "stdin JSON consumed silently when version below threshold" pass
else
  run_test "stdin JSON consumed (exit=$EXIT, out=$OUT)" fail
fi

# Test 30: exit code 0 in all configurations (non-blocking)
EXITS=()
for cfg in \
    "CLAUDE_CODE_VERSION=2.1.153" \
    "CLAUDE_CODE_VERSION=2.1.154" \
    "CLAUDE_CODE_VERSION=2.1.156 CC_VERSION_PIN_ADVISOR_DISABLE=1" \
    "CLAUDE_CODE_VERSION=2.1.156 CC_VERSION_PIN_ADVISOR_QUIET=1" \
    "CLAUDE_CODE_VERSION=2.1.156 CC_VERSION_PIN_ADVISOR_THRESHOLD=2.1.200" \
    "CLAUDE_CODE_VERSION=latest" \
    "CLAUDE_CODE_VERSION=2.1.154-beta"; do
  eval "env -i HOME=\"$HOME\" PATH=\"\$PATH\" $cfg bash \"$HOOK\" >/dev/null 2>&1"
  EXITS+=("$?")
done
ALL_ZERO=1
for e in "${EXITS[@]}"; do
  [ "$e" != "0" ] && ALL_ZERO=0
done
if [ "$ALL_ZERO" = "1" ]; then
  run_test "exit code 0 in all 7 configurations (non-blocking)" pass
else
  run_test "exit code 0 in all configs (got: ${EXITS[*]})" fail
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
