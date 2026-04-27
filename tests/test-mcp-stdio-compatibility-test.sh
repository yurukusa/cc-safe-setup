#!/bin/bash
# Tests for mcp-stdio-compatibility-test.sh
HOOK="examples/mcp-stdio-compatibility-test.sh"
PASS=0 FAIL=0

assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }
assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }

TMPDIR_MCP=$(mktemp -d)

# Test 1: missing settings file exits 2
OUT=$(bash "$HOOK" /nonexistent/path.json 2>&1)
assert_exit "missing settings exits 2" "$?" 2

# Test 2: settings without mcpServers block exits 0 with info
SETTINGS1="$TMPDIR_MCP/settings1.json"
echo '{}' > "$SETTINGS1"
OUT=$(bash "$HOOK" "$SETTINGS1" 2>&1)
assert_exit "empty settings exits 0" "$?" 0
assert_contains "no mcpServers info message" "$OUT" "no mcpServers"

# Test 3: settings with empty mcpServers exits 0
SETTINGS2="$TMPDIR_MCP/settings2.json"
echo '{"mcpServers":{}}' > "$SETTINGS2"
OUT=$(bash "$HOOK" "$SETTINGS2" 2>&1)
assert_exit "empty mcpServers exits 0" "$?" 0

# Test 4: working MCP server returns [ok]
OK_SERVER="$TMPDIR_MCP/ok-server.sh"
cat > "$OK_SERVER" <<'EOF'
#!/bin/bash
read req
echo '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"ok","version":"1.0"}}}'
EOF
chmod +x "$OK_SERVER"
SETTINGS3="$TMPDIR_MCP/settings3.json"
cat > "$SETTINGS3" <<EOF
{"mcpServers":{"ok-server":{"command":"$OK_SERVER","args":[]}}}
EOF
OUT=$(bash "$HOOK" "$SETTINGS3" 2>&1)
assert_exit "working server exits 0" "$?" 0
assert_contains "working server reports ok" "$OUT" "\[ok\]"

# Test 5: regressed server that emits non-JSON is classified as FAIL
BROKEN_SERVER="$TMPDIR_MCP/broken-server.sh"
cat > "$BROKEN_SERVER" <<'EOF'
#!/bin/bash
read req
echo 'not-valid-json-garbage'
EOF
chmod +x "$BROKEN_SERVER"
SETTINGS4="$TMPDIR_MCP/settings4.json"
cat > "$SETTINGS4" <<EOF
{"mcpServers":{"broken-server":{"command":"$BROKEN_SERVER","args":[]}}}
EOF
OUT=$(bash "$HOOK" "$SETTINGS4" 2>&1)
assert_exit "regression exits 1" "$?" 1
assert_contains "regression labeled FAIL" "$OUT" "\[FAIL\]"

# Test 6: auth error is classified separately and does not trigger exit 1
AUTH_SERVER="$TMPDIR_MCP/auth-server.sh"
cat > "$AUTH_SERVER" <<'EOF'
#!/bin/bash
read req
echo '{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"auth token expired"}}'
EOF
chmod +x "$AUTH_SERVER"
SETTINGS5="$TMPDIR_MCP/settings5.json"
cat > "$SETTINGS5" <<EOF
{"mcpServers":{"auth-server":{"command":"$AUTH_SERVER","args":[]}}}
EOF
OUT=$(bash "$HOOK" "$SETTINGS5" 2>&1)
assert_exit "auth error exits 0" "$?" 0
assert_contains "auth error labeled AUTH" "$OUT" "\[AUTH\]"

# Test 7: nonexistent command is skipped, not failed
SETTINGS6="$TMPDIR_MCP/settings6.json"
cat > "$SETTINGS6" <<'EOF'
{"mcpServers":{"missing":{"command":"/definitely/not/here","args":[]}}}
EOF
OUT=$(bash "$HOOK" "$SETTINGS6" 2>&1)
assert_exit "missing command exits 0" "$?" 0
assert_contains "missing command labeled skip" "$OUT" "\[skip\]"

# Test 8: mixed regression + ok yields exit 1
SETTINGS7="$TMPDIR_MCP/settings7.json"
cat > "$SETTINGS7" <<EOF
{"mcpServers":{"ok-server":{"command":"$OK_SERVER","args":[]},"broken-server":{"command":"$BROKEN_SERVER","args":[]}}}
EOF
OUT=$(bash "$HOOK" "$SETTINGS7" 2>&1)
assert_exit "mixed regression exits 1" "$?" 1

# Test 9 (Codex P2): malformed JSON is a config error, not "nothing to test"
SETTINGS_BAD="$TMPDIR_MCP/settings-bad.json"
echo '{this is not json' > "$SETTINGS_BAD"
OUT=$(bash "$HOOK" "$SETTINGS_BAD" 2>&1)
assert_exit "malformed json exits 2" "$?" 2
assert_contains "malformed json error message" "$OUT" "not valid JSON"

# Test 10 (Codex P1): script declares TIMEOUT_CMD fallback for macOS (gtimeout)
# Functional test would need to isolate PATH cleanly; static check is the
# pragmatic compromise given the cross-platform shell-environment friction.
if grep -q 'TIMEOUT_CMD=""' "$HOOK" && grep -q 'gtimeout' "$HOOK"; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "FAIL: timeout/gtimeout fallback logic missing in script"
fi

rm -rf "$TMPDIR_MCP"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
