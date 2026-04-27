#!/bin/bash
# Tests for quota-reset-audit.sh
HOOK="examples/quota-reset-audit.sh"
PASS=0 FAIL=0

assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }
assert_file_contains() { if grep -q "$3" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in $2)"; fi; }

LOG="${HOME}/.claude/logs/usage-audit.log"
mkdir -p "${HOME}/.claude/logs"
: > "$LOG"

STUB_DIR=$(mktemp -d)

# Test 1: claude CLI returns valid /usage JSON — log captures reset fields
cat > "$STUB_DIR/claude" <<'EOF'
#!/bin/bash
echo '{"tier":"max","weekly":{"resets_at":"2026-04-28T00:00:00Z","percent_used":42}}'
EOF
chmod +x "$STUB_DIR/claude"
export PATH="$STUB_DIR:$PATH"

: > "$LOG"
PAYLOAD='{"session_id":"q1"}'
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_exit "happy path exits 0" "$?" 0
assert_file_contains "session id logged" "$LOG" "q1"
assert_file_contains "tier logged" "$LOG" "max"
assert_file_contains "resets_at logged" "$LOG" "2026-04-28T00:00:00Z"
assert_file_contains "percent used logged" "$LOG" "42"

# Test 2: claude CLI absent — log records unavailable placeholder
rm "$STUB_DIR/claude"
: > "$LOG"
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_exit "missing CLI exits 0" "$?" 0
assert_file_contains "unavailable placeholder logged" "$LOG" "unavailable"

# Test 3: claude CLI exists but emits non-JSON — unavailable placeholder
cat > "$STUB_DIR/claude" <<'EOF'
#!/bin/bash
echo "not-json"
EOF
chmod +x "$STUB_DIR/claude"
: > "$LOG"
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_exit "non-JSON exits 0" "$?" 0
assert_file_contains "non-JSON treated as unavailable" "$LOG" "unavailable"

# Test 4: fallback to `claude usage --json` when `claude /usage --json` fails
cat > "$STUB_DIR/claude" <<'EOF'
#!/bin/bash
# First arg determines which style was invoked.
if [ "$1" = "/usage" ]; then
  exit 1
fi
if [ "$1" = "usage" ]; then
  echo '{"tier":"pro","weekly":{"resets_at":"2026-04-27T00:00:00Z","percent_used":10}}'
  exit 0
fi
exit 1
EOF
chmod +x "$STUB_DIR/claude"
: > "$LOG"
printf '%s' "$PAYLOAD" | bash "$HOOK"
assert_exit "fallback path exits 0" "$?" 0
assert_file_contains "fallback resets_at logged" "$LOG" "2026-04-27"
assert_file_contains "fallback tier logged" "$LOG" "pro"

# Test 5: empty input still produces a log line (SessionStart payload can be empty)
: > "$LOG"
printf '' | bash "$HOOK"
assert_exit "empty input exits 0" "$?" 0
# log should have exactly one line
LINES=$(wc -l < "$LOG" | tr -d ' ')
if [ "$LINES" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: expected 1 log line, got $LINES"; fi

rm -rf "$STUB_DIR"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
