#!/bin/bash
# Tests for settings-regression-tester.sh — verifies that a recorded
# version bump triggers a re-verification warning, that the first
# session is silent (no prior state to compare), and that same-version
# sessions stay silent.

HOOK="examples/settings-regression-tester.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

TMPDIR=$(mktemp -d)
PROJ_DIR="$TMPDIR/project"
mkdir -p "$TMPDIR/home/.claude" "$PROJ_DIR/.claude"
STATE_FILE="$TMPDIR/version-state.json"

run_hook() {
    local cwd="$1"
    local version="$2"
    local input
    input=$(jq -n --arg c "$cwd" '{cwd: $c}')
    printf '%s' "$input" | \
        HOME="$TMPDIR/home" \
        CC_SETTINGS_REGRESSION_STATE="$STATE_FILE" \
        CC_SETTINGS_REGRESSION_VERSION_OVERRIDE="$version" \
        bash "$HOOK" 2>&1
}

reset_state() {
    rm -f "$STATE_FILE"
}

# ---- Test 1: first run with no prior state → silent + state written ----
reset_state
OUT=$(run_hook "$PROJ_DIR" "2.1.130")
RC=$?
assert_exit "first run exits 0" "$RC" 0
assert_not_contains "first run silent" "$OUT" "settings-regression"
[ -f "$STATE_FILE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: first run wrote state"; }

# ---- Test 2: same version on next run → still silent ----
OUT=$(run_hook "$PROJ_DIR" "2.1.130")
RC=$?
assert_exit "same version exits 0" "$RC" 0
assert_not_contains "same version no warning" "$OUT" "settings-regression"

# ---- Test 3: version bump → warning surfaces both versions ----
OUT=$(run_hook "$PROJ_DIR" "2.1.131")
RC=$?
assert_exit "bumped version exits 0" "$RC" 0
assert_contains "bumped version warns" "$OUT" "settings-regression"
assert_contains "warning shows old version" "$OUT" "2.1.130"
assert_contains "warning shows new version" "$OUT" "2.1.131"
assert_contains "warning cites #57491" "$OUT" "57491"
assert_contains "warning cites #57486" "$OUT" "57486"

# ---- Test 4: state file updated to the new version after bump ----
RECORDED=$(jq -r '.version' "$STATE_FILE" 2>/dev/null)
[ "$RECORDED" = "2.1.131" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: state updated to bumped version (got $RECORDED)"; }

# ---- Test 5: second bump → still warns and updates ----
OUT=$(run_hook "$PROJ_DIR" "2.1.132")
RC=$?
assert_exit "second bump exits 0" "$RC" 0
assert_contains "second bump warns" "$OUT" "2.1.131"
assert_contains "second bump shows new version" "$OUT" "2.1.132"

# ---- Test 6: BLOCK=1 with bump → exit 2 ----
OUT=$(printf '%s' "$(jq -n --arg c "$PROJ_DIR" '{cwd: $c}')" | \
    HOME="$TMPDIR/home" \
    CC_SETTINGS_REGRESSION_STATE="$STATE_FILE" \
    CC_SETTINGS_REGRESSION_VERSION_OVERRIDE="2.1.140" \
    CC_SETTINGS_REGRESSION_BLOCK=1 \
    bash "$HOOK" 2>&1)
RC=$?
assert_exit "block mode on bump exits 2" "$RC" 2
assert_contains "block mode emits warning text" "$OUT" "settings-regression"

# ---- Test 7: BLOCK=1 with same version → exit 0 ----
OUT=$(printf '%s' "$(jq -n --arg c "$PROJ_DIR" '{cwd: $c}')" | \
    HOME="$TMPDIR/home" \
    CC_SETTINGS_REGRESSION_STATE="$STATE_FILE" \
    CC_SETTINGS_REGRESSION_VERSION_OVERRIDE="2.1.140" \
    CC_SETTINGS_REGRESSION_BLOCK=1 \
    bash "$HOOK" 2>&1)
RC=$?
assert_exit "block mode same version exits 0" "$RC" 0

# ---- Test 8: Allow rules listed in warning ----
reset_state
cat > "$TMPDIR/home/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(npm:*)", "Read(./*)", "Write(./tmp/*)"]
  }
}
EOF
run_hook "$PROJ_DIR" "2.1.140" >/dev/null  # seed
OUT=$(run_hook "$PROJ_DIR" "2.1.141")
RC=$?
assert_exit "allow listing exits 0" "$RC" 0
assert_contains "allow listing surfaces npm" "$OUT" "Bash(npm:\*)"
assert_contains "allow listing surfaces Read" "$OUT" "Read(./\*)"

# ---- Test 9: project-level settings allow rules included ----
reset_state
rm -f "$TMPDIR/home/.claude/settings.json"
cat > "$PROJ_DIR/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(pytest:*)"]
  }
}
EOF
run_hook "$PROJ_DIR" "2.1.150" >/dev/null
OUT=$(run_hook "$PROJ_DIR" "2.1.151")
assert_contains "project allow rule listed" "$OUT" "pytest"

# ---- Test 10: memory: directive surfaced after bump ----
reset_state
cat > "$TMPDIR/home/.claude/settings.json" <<'EOF'
{
  "memory": {
    "include": ["~/notes/*.md"]
  }
}
EOF
run_hook "$PROJ_DIR" "2.1.160" >/dev/null
OUT=$(run_hook "$PROJ_DIR" "2.1.161")
assert_contains "memory directive flagged" "$OUT" "memory directives present"
assert_contains "memory directive points at file" "$OUT" "settings.json"

# ---- Test 11: empty input still records state ----
reset_state
OUT=$(printf '' | \
    HOME="$TMPDIR/home" \
    CC_SETTINGS_REGRESSION_STATE="$STATE_FILE" \
    CC_SETTINGS_REGRESSION_VERSION_OVERRIDE="2.1.170" \
    bash "$HOOK" 2>&1)
RC=$?
assert_exit "empty stdin exits 0" "$RC" 0
[ -f "$STATE_FILE" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: empty stdin still wrote state"; }

# ---- Test 12: claude not on PATH and no override → silent ----
reset_state
# Build a minimal sandbox PATH that has core utilities but no `claude`.
SANDBOX_BIN="$TMPDIR/sandbox-bin"
mkdir -p "$SANDBOX_BIN"
for util in bash jq cat awk sed grep mkdir rm head sort sha256sum date sleep printf command; do
    src=$(command -v "$util" 2>/dev/null) || continue
    ln -sf "$src" "$SANDBOX_BIN/$util" 2>/dev/null || true
done
OUT=$(echo '{}' | \
    HOME="$TMPDIR/home" \
    CC_SETTINGS_REGRESSION_STATE="$STATE_FILE" \
    PATH="$SANDBOX_BIN" \
    bash "$HOOK" 2>&1)
RC=$?
assert_exit "no claude binary exits 0" "$RC" 0
assert_not_contains "no claude binary silent" "$OUT" "settings-regression"

# ---- Test 13: real-world #57491 repro — npm allow rule re-prompt ----
reset_state
cat > "$TMPDIR/home/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(npm:test)", "Bash(npm:run)"]
  }
}
EOF
run_hook "$PROJ_DIR" "2.1.127" >/dev/null
OUT=$(run_hook "$PROJ_DIR" "2.1.128")
assert_contains "#57491 repro names old version" "$OUT" "2.1.127"
assert_contains "#57491 repro names new version" "$OUT" "2.1.128"
assert_contains "#57491 repro lists npm rule" "$OUT" "npm:test"

# ---- Test 14: hashes recorded even when settings absent ----
reset_state
rm -f "$TMPDIR/home/.claude/settings.json" "$PROJ_DIR/.claude/settings.json"
run_hook "$PROJ_DIR" "2.1.180" >/dev/null
USER_H=$(jq -r '.hashes.user' "$STATE_FILE" 2>/dev/null)
[ "$USER_H" = "" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: absent settings → empty hash (got '$USER_H')"; }

# ---- Test 15: bump with no settings files → still warns about version ----
OUT=$(run_hook "$PROJ_DIR" "2.1.181")
assert_contains "bump w/o settings still warns" "$OUT" "2.1.181"
assert_not_contains "bump w/o settings has no allow listing" "$OUT" "Active Allow rules"

# Cleanup
rm -rf "$TMPDIR"

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && echo "OK" || exit 1
