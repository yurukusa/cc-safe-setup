#!/bin/bash
# Tests for cowork-claudemd-helper.sh
HELPER="scripts/cowork-claudemd-helper.sh"
PASS=0 FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

assert_contains() { if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected '$3')"; fi; }
assert_not_contains() { if ! echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (unexpected '$3')"; fi; }
assert_exit() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected exit $3, got $2)"; fi; }

HELPER_ABS="$PWD/$HELPER"

# Test 1: No user CLAUDE.md, no project → informative stderr, exit 0
OUT=$(CC_COWORK_HELPER_USER_PATH="$TMPDIR/none/CLAUDE.md" bash "$HELPER_ABS" 2>&1); RC=$?
assert_contains "no file informative" "$OUT" "no CLAUDE.md found"
assert_exit "no file exit 0" "$RC" "0"

# Test 2: User CLAUDE.md only → printed with header
USER_FILE="$TMPDIR/user-claude.md"
printf "Always ask for confirmation before write operations.\nNever use --force flags.\n" > "$USER_FILE"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" 2>/dev/null); RC=$?
assert_contains "user file content printed" "$OUT" "Always ask for confirmation"
assert_contains "user file path shown" "$OUT" "$USER_FILE"
assert_contains "default header present" "$OUT" "Standing instructions"
assert_contains "section header present" "$OUT" "User-scoped"
assert_contains "footer cites issue" "$OUT" "#62859"
assert_exit "user file exit 0" "$RC" "0"

# Test 3: --paths lists only existing files
USER_FILE="$TMPDIR/user2-claude.md"
echo "test instructions" > "$USER_FILE"
PROJ="$TMPDIR/proj2"
mkdir -p "$PROJ/.claude"
echo "project instructions" > "$PROJ/.claude/CLAUDE.md"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" --paths "$PROJ" 2>/dev/null); RC=$?
assert_contains "paths lists user" "$OUT" "user2-claude.md"
assert_contains "paths lists project" "$OUT" "proj2/.claude/CLAUDE.md"
assert_exit "paths exit 0" "$RC" "0"

# Test 4: Project flag — both user and project printed when both exist
USER_FILE="$TMPDIR/user3.md"
echo "user-level rule" > "$USER_FILE"
PROJ="$TMPDIR/proj3"
mkdir -p "$PROJ/.claude"
echo "project-level rule" > "$PROJ/.claude/CLAUDE.md"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" "$PROJ" 2>/dev/null); RC=$?
assert_contains "both printed - user" "$OUT" "user-level rule"
assert_contains "both printed - project" "$OUT" "project-level rule"
assert_contains "both - user header" "$OUT" "User-scoped"
assert_contains "both - project header" "$OUT" "Project-scoped"
assert_exit "both exit 0" "$RC" "0"

# Test 5: Project flag — user only when project doesn't have CLAUDE.md
USER_FILE="$TMPDIR/user5.md"
echo "only user" > "$USER_FILE"
PROJ_NONE="$TMPDIR/proj5-empty"
mkdir -p "$PROJ_NONE"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" "$PROJ_NONE" 2>/dev/null); RC=$?
assert_contains "user only - user content" "$OUT" "only user"
assert_not_contains "user only - no project section" "$OUT" "Project-scoped"
assert_exit "user only exit 0" "$RC" "0"

# Test 6: Project only when user CLAUDE.md missing
USER_NONE="$TMPDIR/no-user.md"
PROJ6="$TMPDIR/proj6"
mkdir -p "$PROJ6/.claude"
echo "project only rule" > "$PROJ6/.claude/CLAUDE.md"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_NONE" bash "$HELPER_ABS" "$PROJ6" 2>/dev/null); RC=$?
assert_contains "project only - content" "$OUT" "project only rule"
assert_not_contains "project only - no user section" "$OUT" "User-scoped"
assert_exit "project only exit 0" "$RC" "0"

# Test 7: Custom header via env var
USER_FILE="$TMPDIR/user7.md"
echo "rule" > "$USER_FILE"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" \
      CC_COWORK_HELPER_HEADER="My custom paste header:" \
      bash "$HELPER_ABS" 2>/dev/null); RC=$?
assert_contains "custom header used" "$OUT" "My custom paste header"
assert_not_contains "default header absent" "$OUT" "Standing instructions"
assert_exit "custom header exit 0" "$RC" "0"

# Test 8: Trailing slash on project path normalized
USER_FILE="$TMPDIR/user8.md"
echo "u" > "$USER_FILE"
PROJ8="$TMPDIR/proj8"
mkdir -p "$PROJ8/.claude"
echo "p" > "$PROJ8/.claude/CLAUDE.md"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" "$PROJ8/" 2>/dev/null); RC=$?
assert_contains "trailing slash works" "$OUT" "p"
assert_exit "trailing slash exit 0" "$RC" "0"

# Test 9: --paths with no files lists nothing
OUT=$(CC_COWORK_HELPER_USER_PATH="$TMPDIR/missing.md" bash "$HELPER_ABS" --paths 2>/dev/null); RC=$?
if [ -z "$OUT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: paths with no files outputs nothing (got: $OUT)"; fi
assert_exit "paths empty exit 0" "$RC" "0"

# Test 10: Help flag
OUT=$(bash "$HELPER_ABS" --help 2>/dev/null); RC=$?
assert_contains "help shows purpose" "$OUT" "PURPOSE"
assert_contains "help cites issue" "$OUT" "#62859"
assert_exit "help exit 0" "$RC" "0"

# Test 11: --copy without clipboard tool falls back to stdout (PATH stripped)
USER_FILE="$TMPDIR/user11.md"
echo "fallback content" > "$USER_FILE"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" PATH=/usr/bin:/bin bash "$HELPER_ABS" --copy 2>&1); RC=$?
# Skip this test if pbcopy/wl-copy/xclip happen to be in /usr/bin or /bin
if ! command -v pbcopy >/dev/null 2>&1 && ! command -v wl-copy >/dev/null 2>&1 && ! command -v xclip >/dev/null 2>&1; then
    assert_contains "copy fallback content" "$OUT" "fallback content"
fi
assert_exit "copy fallback exit 0" "$RC" "0"

# Test 12: Project given but user CLAUDE.md missing and project missing → informative
USER_NONE="$TMPDIR/none12.md"
PROJ_NONE="$TMPDIR/proj12-empty"
mkdir -p "$PROJ_NONE"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_NONE" bash "$HELPER_ABS" "$PROJ_NONE" 2>&1); RC=$?
assert_contains "both missing informative" "$OUT" "no CLAUDE.md found"
assert_exit "both missing exit 0" "$RC" "0"

# Test 13: Output ends with footer line citing issue
USER_FILE="$TMPDIR/user13.md"
echo "x" > "$USER_FILE"
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" 2>/dev/null); RC=$?
LAST_LINE=$(echo "$OUT" | grep -v '^$' | tail -1)
assert_contains "footer is last meaningful line" "$LAST_LINE" "62859"
assert_exit "footer exit 0" "$RC" "0"

# Test 14: Unreadable file falls through (chmod 0)
USER_FILE="$TMPDIR/user14.md"
echo "secret" > "$USER_FILE"
chmod 000 "$USER_FILE" 2>/dev/null
OUT=$(CC_COWORK_HELPER_USER_PATH="$USER_FILE" bash "$HELPER_ABS" 2>&1); RC=$?
assert_contains "unreadable treated as missing" "$OUT" "no CLAUDE.md found"
chmod 644 "$USER_FILE" 2>/dev/null
assert_exit "unreadable exit 0" "$RC" "0"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
