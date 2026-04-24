#!/bin/bash
# Tests for claude-update-smart.sh
HOOK="examples/claude-update-smart.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

TMPCACHE=$(mktemp)
rm -f "$TMPCACHE"
export CLAUDE_UPDATE_SMART_CACHE="$TMPCACHE"
export CLAUDE_UPDATE_SMART_NO_EXEC=1

# Test 1: up-to-date → skip
OUT=$(CLAUDE_UPDATE_SMART_LOCAL="2.1.118" CLAUDE_UPDATE_SMART_LATEST="2.1.118" bash "$HOOK" 2>&1)
RC=$?
assert_exit "skip when up-to-date exits 0" "$RC" 0
assert_contains "skip message references #51243" "$OUT" "#51243"
assert_contains "skip message says up to date" "$OUT" "up to date"
assert_contains "decision line is skip" "$OUT" "decision=skip"

# Test 2: update available → would run `claude update`
OUT=$(CLAUDE_UPDATE_SMART_LOCAL="2.1.114" CLAUDE_UPDATE_SMART_LATEST="2.1.119" bash "$HOOK" 2>&1)
RC=$?
assert_exit "update path exits 0 in NO_EXEC mode" "$RC" 0
assert_contains "announces version diff" "$OUT" "2.1.114"
assert_contains "announces target version" "$OUT" "2.1.119"
assert_contains "decision line is update" "$OUT" "decision=update"

# Test 3: cannot determine latest (stub npm + curl to empty, LATEST env blank)
STUB_DIR=$(mktemp -d)
cat >"$STUB_DIR/npm" <<'EOF'
#!/bin/sh
exit 1
EOF
cat >"$STUB_DIR/curl" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_DIR/npm" "$STUB_DIR/curl"
OUT=$(CLAUDE_UPDATE_SMART_LOCAL="2.1.118" PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" 2>&1)
RC=$?
# In NO_EXEC mode, we expect a fallthrough with decision=fallthrough and exit 2
assert_exit "fallthrough when latest unknown exits 2" "$RC" 2
assert_contains "fallthrough note printed" "$OUT" "fallthrough"
rm -rf "$STUB_DIR"

# Test 4: cache is written when a successful lookup occurs
rm -f "$TMPCACHE"
CLAUDE_UPDATE_SMART_LOCAL="2.1.118" CLAUDE_UPDATE_SMART_LATEST="2.1.119" bash "$HOOK" >/dev/null 2>&1
# Note: when LATEST is provided via env, the script intentionally does NOT write the cache
# (cache is only for network-resolved lookups). So the cache should NOT exist here.
if [ ! -s "$TMPCACHE" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: cache should not be written when LATEST overridden"; fi

# Test 5: local version not found → falls through with exit 127 in NO_EXEC
STUB_DIR=$(mktemp -d)
OUT=$(CLAUDE_UPDATE_SMART_LOCAL="" PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" 2>&1)
RC=$?
assert_exit "no claude binary exits 127" "$RC" 127
rm -rf "$STUB_DIR"

# Test 6: manually seeded cache is honored (no override of LATEST env)
rm -f "$TMPCACHE"
printf '{"latest":"2.1.120","checked_at":%s}\n' "$(date +%s)" > "$TMPCACHE"
OUT=$(CLAUDE_UPDATE_SMART_LOCAL="2.1.120" bash "$HOOK" 2>&1)
RC=$?
assert_exit "cache-hit up-to-date exits 0" "$RC" 0
assert_contains "cache-hit says up to date" "$OUT" "up to date"

# Test 7: stale cache is ignored (TTL=1, file mtime set 10 s in the past)
rm -f "$TMPCACHE"
printf '{"latest":"2.1.120","checked_at":%s}\n' "$(($(date +%s) - 10))" > "$TMPCACHE"
touch -d "10 seconds ago" "$TMPCACHE"
STUB_DIR=$(mktemp -d)
cat >"$STUB_DIR/npm" <<'EOF'
#!/bin/sh
exit 1
EOF
cat >"$STUB_DIR/curl" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$STUB_DIR/npm" "$STUB_DIR/curl"
OUT=$(CLAUDE_UPDATE_SMART_LOCAL="2.1.120" CLAUDE_UPDATE_SMART_TTL=1 PATH="$STUB_DIR:/usr/bin:/bin" bash "$HOOK" 2>&1)
RC=$?
assert_exit "stale cache + no network → fallthrough exit 2" "$RC" 2
rm -rf "$STUB_DIR"

rm -f "$TMPCACHE"
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
