#!/bin/bash
# Tests for settings-json-health-check.sh
HOOK="examples/settings-json-health-check.sh"
PASS=0 FAIL=0

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3' in: $2)"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3' in: $2)"; fi; }
assert_exit() { if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (exit $2, expected $3)"; fi; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

USER_GOOD="$TMPDIR/user-good.json"
USER_BAD="$TMPDIR/user-bad.json"
PROJ_GOOD="$TMPDIR/proj-good.json"
PROJ_BAD="$TMPDIR/proj-bad.json"

printf '{"permissions":{"allow":["Read"]}}\n' > "$USER_GOOD"
printf '{not valid json\n' > "$USER_BAD"
printf '{"hooks":{}}\n' > "$PROJ_GOOD"
printf '{"hooks": [unclosed\n' > "$PROJ_BAD"

# Test 1: Both good → exits 0, no warnings
OUT=$(SETTINGS_HEALTH_USER_PATH="$USER_GOOD" SETTINGS_HEALTH_PROJECT_PATH="$PROJ_GOOD" CC_SKIP_DOCTOR_CHECK=1 bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "both good exits 0" "$RC" 0
assert_not_contains "no warning when good" "$OUT" "settings-json-health-check"

# Test 2: User settings bad → exits non-zero with warning
OUT=$(SETTINGS_HEALTH_USER_PATH="$USER_BAD" SETTINGS_HEALTH_PROJECT_PATH="$PROJ_GOOD" CC_SKIP_DOCTOR_CHECK=1 bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "bad user settings exits 2" "$RC" 2
assert_contains "warning names the path" "$OUT" "user-bad.json"
assert_contains "warning mentions backup" "$OUT" "backup"
# Backup file should exist
if ls "$USER_BAD".broken.* >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: backup file not created"; fi

# Test 3: Project settings bad → also exits non-zero
rm -f "$USER_BAD".broken.*
OUT=$(SETTINGS_HEALTH_USER_PATH="$USER_GOOD" SETTINGS_HEALTH_PROJECT_PATH="$PROJ_BAD" CC_SKIP_DOCTOR_CHECK=1 bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "bad project settings exits 2" "$RC" 2

# Test 4: Missing files → treated as clean (nothing to check) exit 0
OUT=$(SETTINGS_HEALTH_USER_PATH="$TMPDIR/nope1.json" SETTINGS_HEALTH_PROJECT_PATH="$TMPDIR/nope2.json" CC_SKIP_DOCTOR_CHECK=1 bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "missing files exits 0" "$RC" 0

# Test 5: /doctor dismissed sentinel triggers notice (simulated)
FAKE_DOCTOR="$TMPDIR/doctor-sim"
mkdir -p "$FAKE_DOCTOR"
touch "$FAKE_DOCTOR/doctor-dismissed-v1"
# The hook looks in $HOME/.claude, so use a tmp HOME for this test
export HOME_BAK="$HOME"
export HOME="$TMPDIR"
mkdir -p "$HOME/.claude"
touch "$HOME/.claude/doctor-dismissed-v1"
OUT=$(SETTINGS_HEALTH_USER_PATH="$USER_GOOD" SETTINGS_HEALTH_PROJECT_PATH="$PROJ_GOOD" bash "$HOOK" </dev/null 2>&1)
RC=$?
export HOME="$HOME_BAK"
assert_contains "doctor dismissed notice fires" "$OUT" "/doctor diagnostic has been dismissed"

# Test 6: CC_SKIP_DOCTOR_CHECK=1 suppresses the notice
export HOME="$TMPDIR"
OUT=$(SETTINGS_HEALTH_USER_PATH="$USER_GOOD" SETTINGS_HEALTH_PROJECT_PATH="$PROJ_GOOD" CC_SKIP_DOCTOR_CHECK=1 bash "$HOOK" </dev/null 2>&1)
export HOME="$HOME_BAK"
assert_not_contains "skip flag suppresses doctor notice" "$OUT" "/doctor diagnostic has been dismissed"

echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
