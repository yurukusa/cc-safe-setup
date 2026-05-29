#!/bin/bash
# test-ultrareview-large-diff-advisor.sh — Tests for Cluster 18
# candidate /ultrareview large-diff SessionStart advisory.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../examples/ultrareview-large-diff-advisor.sh"

if [ ! -x "$HOOK" ]; then
    chmod +x "$HOOK"
fi

PASS=0
FAIL=0
TOTAL=0

# Build a tiny git repo on demand with a "main" branch and an
# arbitrary number of changed files / inserted lines on HEAD.
make_repo() {
    local dir="$1"
    local files="$2"
    local lines_per_file="$3"
    local base_branch="${4:-main}"
    rm -rf "$dir"
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q -b "$base_branch" >/dev/null 2>&1
        git config user.email "test@example.com"
        git config user.name "Test"
        echo "seed" > seed.txt
        git add seed.txt
        git commit -q -m "seed" >/dev/null 2>&1
        git checkout -q -b feature
        local i j
        for i in $(seq 1 "$files"); do
            for j in $(seq 1 "$lines_per_file"); do
                echo "line $j of file $i" >> "file_${i}.txt"
            done
            git add "file_${i}.txt"
        done
        if [ "$files" -gt 0 ]; then
            git commit -q -m "add" >/dev/null 2>&1
        fi
    )
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    case "$haystack" in
        *"$needle"*)
            PASS=$((PASS + 1))
            echo "  PASS: $desc"
            ;;
        *)
            FAIL=$((FAIL + 1))
            echo "  FAIL: $desc — needle not found"
            echo "    needle:   $needle"
            echo "    haystack: $haystack"
            ;;
    esac
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    case "$haystack" in
        *"$needle"*)
            FAIL=$((FAIL + 1))
            echo "  FAIL: $desc — needle should not appear"
            echo "    needle: $needle"
            ;;
        *)
            PASS=$((PASS + 1))
            echo "  PASS: $desc"
            ;;
    esac
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Test 1: DISABLE=1 produces silent output
make_repo "$TMP/r1" 20 100
OUT=$(CC_ULTRAREVIEW_ADVISOR_DISABLE=1 CC_ULTRAREVIEW_GIT_DIR="$TMP/r1" "$HOOK" </dev/null 2>&1)
assert_eq "Test 1: DISABLE=1 silent" "" "$OUT"

# Test 2: QUIET=1 produces silent output
OUT=$(CC_ULTRAREVIEW_ADVISOR_QUIET=1 CC_ULTRAREVIEW_GIT_DIR="$TMP/r1" "$HOOK" </dev/null 2>&1)
assert_eq "Test 2: QUIET=1 silent" "" "$OUT"

# Test 3: Non-git directory: silent (fail open)
mkdir -p "$TMP/non-git"
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/non-git" "$HOOK" </dev/null 2>&1)
assert_eq "Test 3: non-git dir silent" "" "$OUT"

# Test 4: Missing base branch: silent
make_repo "$TMP/r4" 20 100 trunk
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r4" "$HOOK" </dev/null 2>&1)
assert_eq "Test 4: missing 'main' base silent" "" "$OUT"

# Test 5: Below WARN file and line: silent
make_repo "$TMP/r5" 3 50
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r5" "$HOOK" </dev/null 2>&1)
assert_eq "Test 5: small diff silent (3 files / 150 lines)" "" "$OUT"

# Test 6: Zero changes (same as base): silent
make_repo "$TMP/r6" 0 0
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r6" "$HOOK" </dev/null 2>&1)
assert_eq "Test 6: zero diff silent" "" "$OUT"

# Test 7: WARN-tier by file count (6 files at 50 lines each = 300 lines, < LINES_WARN 500)
make_repo "$TMP/r7" 6 50
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r7" "$HOOK" </dev/null 2>&1)
assert_contains "Test 7a: 6 files triggers caution" "caution range" "$OUT"
assert_not_contains "Test 7b: caution is not elevated" "elevated rate" "$OUT"

# Test 8: BLOCK-tier by file count (20 files at 10 lines each = 200 lines, < LINES_WARN)
make_repo "$TMP/r8" 20 10
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r8" "$HOOK" </dev/null 2>&1)
assert_contains "Test 8a: 20 files triggers elevated" "elevated rate" "$OUT"
assert_not_contains "Test 8b: elevated not caution" "caution range" "$OUT"

# Test 9: WARN-tier by line count (5 files at 120 lines = 600 lines, files < WARN 6)
make_repo "$TMP/r9" 5 120
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r9" "$HOOK" </dev/null 2>&1)
assert_contains "Test 9: 600 lines triggers caution" "caution range" "$OUT"

# Test 10: BLOCK-tier by line count (5 files at 400 lines = 2000 lines)
make_repo "$TMP/r10" 5 400
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r10" "$HOOK" </dev/null 2>&1)
assert_contains "Test 10: 2000 lines triggers elevated" "elevated rate" "$OUT"

# Test 11: Custom WARN threshold honored
make_repo "$TMP/r11" 4 50
OUT=$(CC_ULTRAREVIEW_FILES_WARN=4 CC_ULTRAREVIEW_GIT_DIR="$TMP/r11" "$HOOK" </dev/null 2>&1)
assert_contains "Test 11: FILES_WARN=4 triggers at 4 files" "caution range" "$OUT"

# Test 12: Malformed thresholds fall back to defaults silently (still warns)
make_repo "$TMP/r12" 6 50
OUT=$(CC_ULTRAREVIEW_FILES_WARN=abc CC_ULTRAREVIEW_GIT_DIR="$TMP/r12" "$HOOK" </dev/null 2>&1)
assert_contains "Test 12: malformed FILES_WARN falls back to default 6" "caution range" "$OUT"

# Test 13: Custom base branch honored
make_repo "$TMP/r13" 6 50 develop
OUT=$(CC_ULTRAREVIEW_BRANCH_BASE=develop CC_ULTRAREVIEW_GIT_DIR="$TMP/r13" "$HOOK" </dev/null 2>&1)
assert_contains "Test 13: custom BRANCH_BASE=develop triggers correctly" "caution range" "$OUT"

# Test 14: stdin consumed without error
make_repo "$TMP/r14" 6 50
OUT=$(echo '{"hookEvent":"SessionStart"}' | CC_ULTRAREVIEW_GIT_DIR="$TMP/r14" "$HOOK" 2>&1)
assert_contains "Test 14: stdin JSON consumed cleanly" "caution range" "$OUT"

# Test 15: Advisory mentions three-axis defense
make_repo "$TMP/r15" 20 100
OUT=$(CC_ULTRAREVIEW_GIT_DIR="$TMP/r15" "$HOOK" </dev/null 2>&1)
assert_contains "Test 15a: defense 1 — split PR" "Split the PR" "$OUT"
assert_contains "Test 15b: defense 2 — do not retry" "Do not retry" "$OUT"
assert_contains "Test 15c: defense 3 — fall back to /code-review" "/code-review" "$OUT"

# Test 16: Advisory mentions the anchor issue and field guide
assert_contains "Test 16a: anchor issue URL present" "62696" "$OUT"
assert_contains "Test 16b: field guide URL present" "f7363d83e3f4bcbb1bd7cf66a1c64752" "$OUT"

# Test 17: Hook exits 0 even when warning
make_repo "$TMP/r17" 20 100
CC_ULTRAREVIEW_GIT_DIR="$TMP/r17" "$HOOK" </dev/null >/dev/null 2>&1
EXIT=$?
assert_eq "Test 17: hook exit code is 0 when warning" "0" "$EXIT"

echo ""
echo "Results: $PASS / $TOTAL passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
