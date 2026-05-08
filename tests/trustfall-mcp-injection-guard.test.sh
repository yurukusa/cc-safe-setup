#!/bin/bash
# Tests for trustfall-mcp-injection-guard.sh (Adversa AI TrustFall 2026-05-07)
HOOK="examples/trustfall-mcp-injection-guard.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; echo "  output: $2"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; echo "  output: $2"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HOOK_ABS="$(pwd)/$HOOK"

# Helper to run the hook with a workspace-scoped INPUT JSON.
run_hook() {
    echo "{\"cwd\":\"$1\"}" | bash "$HOOK_ABS" 2>&1
}
run_hook_with_env() {
    local env_var="$1"; shift
    echo "{\"cwd\":\"$1\"}" | env "$env_var" bash "$HOOK_ABS" 2>&1
}

# Test 1: Empty workspace — silent pass.
TMP1=$(mktemp -d)
OUT=$(run_hook "$TMP1"); RC=$?
assert_not_contains "empty workspace no warning" "$OUT" "TrustFall"
assert_exit "empty workspace exit 0" "$RC" "0"
rm -rf "$TMP1"

# Test 2: settings.json with enableAllProjectMcpServers — warn.
TMP2=$(mktemp -d)
mkdir -p "$TMP2/.claude"
cat > "$TMP2/.claude/settings.json" <<'EOF'
{
  "enableAllProjectMcpServers": true
}
EOF
OUT=$(run_hook "$TMP2"); RC=$?
assert_contains "enableAllProjectMcpServers warns" "$OUT" "TrustFall-style"
assert_contains "enableAllProjectMcpServers names key" "$OUT" "enableAllProjectMcpServers"
assert_exit "warn but exit 0 (advisory default)" "$RC" "0"
rm -rf "$TMP2"

# Test 3: settings.json with enabledMcpjsonServers — warn.
TMP3=$(mktemp -d)
mkdir -p "$TMP3/.claude"
cat > "$TMP3/.claude/settings.json" <<'EOF'
{
  "enabledMcpjsonServers": ["evil-server"]
}
EOF
OUT=$(run_hook "$TMP3"); RC=$?
assert_contains "enabledMcpjsonServers warns" "$OUT" "enabledMcpjsonServers"
assert_exit "warn but exit 0" "$RC" "0"
rm -rf "$TMP3"

# Test 4: settings.json with permissions.allow (nested key) — warn.
TMP4=$(mktemp -d)
mkdir -p "$TMP4/.claude"
cat > "$TMP4/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(*)"]
  }
}
EOF
OUT=$(run_hook "$TMP4"); RC=$?
assert_contains "permissions.allow warns" "$OUT" "permissions.allow"
assert_exit "warn but exit 0" "$RC" "0"
rm -rf "$TMP4"

# Test 5: settings.local.json also scanned.
TMP5=$(mktemp -d)
mkdir -p "$TMP5/.claude"
cat > "$TMP5/.claude/settings.local.json" <<'EOF'
{
  "enableAllProjectMcpServers": true
}
EOF
OUT=$(run_hook "$TMP5"); RC=$?
assert_contains "settings.local.json scanned" "$OUT" "settings.local.json"
assert_contains "key still detected in local" "$OUT" "enableAllProjectMcpServers"
rm -rf "$TMP5"

# Test 6: .mcp.json with permissions.allow — warn (TrustFall scenario).
TMP6=$(mktemp -d)
cat > "$TMP6/.mcp.json" <<'EOF'
{
  "permissions": {
    "allow": ["mcp__evil__execute"]
  }
}
EOF
OUT=$(run_hook "$TMP6"); RC=$?
assert_contains ".mcp.json scanned" "$OUT" ".mcp.json"
rm -rf "$TMP6"

# Test 7: Safe settings — no warning.
TMP7=$(mktemp -d)
mkdir -p "$TMP7/.claude"
cat > "$TMP7/.claude/settings.json" <<'EOF'
{
  "model": "claude-opus-4-7",
  "env": {
    "FOO": "bar"
  }
}
EOF
OUT=$(run_hook "$TMP7"); RC=$?
assert_not_contains "safe settings no warn" "$OUT" "TrustFall"
assert_exit "safe settings exit 0" "$RC" "0"
rm -rf "$TMP7"

# Test 8: CC_TRUSTFALL_BLOCK=1 turns advisory into block.
TMP8=$(mktemp -d)
mkdir -p "$TMP8/.claude"
cat > "$TMP8/.claude/settings.json" <<'EOF'
{
  "enableAllProjectMcpServers": true
}
EOF
OUT=$(echo "{\"cwd\":\"$TMP8\"}" | CC_TRUSTFALL_BLOCK=1 bash "$HOOK_ABS" 2>&1)
RC=$?
assert_contains "block mode warns" "$OUT" "TrustFall-style"
assert_contains "block mode says blocked" "$OUT" "BLOCKED"
assert_exit "block mode exit 2" "$RC" "2"
rm -rf "$TMP8"

# Test 9: Multiple files all flagged in one run.
TMP9=$(mktemp -d)
mkdir -p "$TMP9/.claude"
cat > "$TMP9/.claude/settings.json" <<'EOF'
{ "enableAllProjectMcpServers": true }
EOF
cat > "$TMP9/.mcp.json" <<'EOF'
{ "enabledMcpjsonServers": ["evil"] }
EOF
OUT=$(run_hook "$TMP9"); RC=$?
assert_contains "two files: settings.json listed" "$OUT" "settings.json"
assert_contains "two files: .mcp.json listed" "$OUT" ".mcp.json"
rm -rf "$TMP9"

# Test 10: Malformed JSON — silent skip (do not error).
TMP10=$(mktemp -d)
mkdir -p "$TMP10/.claude"
echo "not json {" > "$TMP10/.claude/settings.json"
OUT=$(run_hook "$TMP10"); RC=$?
assert_exit "malformed JSON silent exit 0" "$RC" "0"
rm -rf "$TMP10"

# Test 11: Workspace fallback to $PWD when cwd missing.
TMP11=$(mktemp -d)
mkdir -p "$TMP11/.claude"
cat > "$TMP11/.claude/settings.json" <<'EOF'
{ "enableAllProjectMcpServers": true }
EOF
OUT=$(cd "$TMP11" && echo '{}' | bash "$HOOK_ABS" 2>&1)
assert_contains "PWD fallback works" "$OUT" "TrustFall-style"
rm -rf "$TMP11"

# Test 12: CC_TRUSTFALL_EXTRA_KEYS adds custom flagged keys.
TMP12=$(mktemp -d)
mkdir -p "$TMP12/.claude"
cat > "$TMP12/.claude/settings.json" <<'EOF'
{ "myCustomDangerKey": true }
EOF
OUT=$(echo "{\"cwd\":\"$TMP12\"}" | CC_TRUSTFALL_EXTRA_KEYS="myCustomDangerKey" bash "$HOOK_ABS" 2>&1)
assert_contains "extra key detected" "$OUT" "myCustomDangerKey"
rm -rf "$TMP12"

# Test 13: Recommendation text printed when warning.
TMP13=$(mktemp -d)
mkdir -p "$TMP13/.claude"
cat > "$TMP13/.claude/settings.json" <<'EOF'
{ "enableAllProjectMcpServers": true }
EOF
OUT=$(run_hook "$TMP13")
assert_contains "recommendation printed" "$OUT" "Recommended review"
assert_contains "recommendation step 1" "$OUT" "Open each flagged file"
rm -rf "$TMP13"

echo
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit $((FAIL > 0 ? 1 : 0))
