#!/bin/bash
# Tests for skill-cumulative-size-detector.sh
# Run: bash tests/test-skill-cumulative-size-detector.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/skill-cumulative-size-detector.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Build a fake SKILL.md tree of the requested cumulative byte size.
# $1 = base dir (e.g. $HOME/.claude/skills or .claude/skills)
# $2 = total bytes to distribute across SKILL.md files
# $3 = number of skills to create
seed_skills() {
    local base="$1"
    local total="$2"
    local count="$3"
    [ "$count" -le 0 ] && return 0
    mkdir -p "$base"
    local per=$((total / count))
    [ "$per" -le 0 ] && per=1
    local i=0
    while [ "$i" -lt "$count" ]; do
        local dir="$base/skill_$i"
        mkdir -p "$dir"
        # Pad with deterministic ASCII so the size is exact-ish.
        head -c "$per" /dev/zero | tr '\0' '.' > "$dir/SKILL.md"
        i=$((i + 1))
    done
}

run_hook() {
    local home_dir="$1"
    local cwd_dir="$2"
    local extra_env="${3:-}"
    if [ -n "$extra_env" ]; then
        echo '{}' | env -i HOME="$home_dir" PATH="$PATH" $extra_env bash -c "cd \"$cwd_dir\" && \"$HOOK\"" 2>&1
    else
        echo '{}' | env -i HOME="$home_dir" PATH="$PATH" bash -c "cd \"$cwd_dir\" && \"$HOOK\"" 2>&1
    fi
}

run_hook_exit() {
    local home_dir="$1"
    local cwd_dir="$2"
    local extra_env="${3:-}"
    if [ -n "$extra_env" ]; then
        echo '{}' | env -i HOME="$home_dir" PATH="$PATH" $extra_env bash -c "cd \"$cwd_dir\" && \"$HOOK\"" >/dev/null 2>&1
    else
        echo '{}' | env -i HOME="$home_dir" PATH="$PATH" bash -c "cd \"$cwd_dir\" && \"$HOOK\"" >/dev/null 2>&1
    fi
    return $?
}

assert_silent() {
    local label="$1"
    local output="$2"
    if [ -z "$output" ]; then
        echo "PASS: $label (silent)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (expected silent, got: $output)"
        FAIL=$((FAIL + 1))
    fi
}

assert_warned() {
    local label="$1"
    local output="$2"
    local expected_marker="$3"
    if echo "$output" | grep -qF "$expected_marker"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (expected '$expected_marker' in output)"
        echo "  output: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_zero() {
    local label="$1"
    local actual="$2"
    if [ "$actual" -eq 0 ]; then
        echo "PASS: $label (exit 0)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (expected exit 0, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ---------- Test 1: no skills at all → silent, exit 0 ----------
H1="$WORK_DIR/h1"
P1="$WORK_DIR/p1"
mkdir -p "$H1" "$P1"
OUT1=$(run_hook "$H1" "$P1")
assert_silent "empty environment produces no output" "$OUT1"
run_hook_exit "$H1" "$P1"
assert_exit_zero "empty environment" $?

# ---------- Test 2: below warning threshold → silent ----------
H2="$WORK_DIR/h2"
P2="$WORK_DIR/p2"
mkdir -p "$H2" "$P2"
seed_skills "$H2/.claude/skills" 5000 5
OUT2=$(run_hook "$H2" "$P2")
assert_silent "below warning threshold (5KB, 5 skills) is silent" "$OUT2"

# ---------- Test 3: above warn, below hard → soft warning ----------
H3="$WORK_DIR/h3"
P3="$WORK_DIR/p3"
mkdir -p "$H3" "$P3"
seed_skills "$H3/.claude/skills" 30000 30
OUT3=$(run_hook "$H3" "$P3")
assert_warned "above soft threshold (30KB) emits [WARN]" "$OUT3" "[WARN] Cumulative skill description size"
run_hook_exit "$H3" "$P3"
assert_exit_zero "soft warning still advisory" $?

# ---------- Test 4: above hard → hard warning ----------
H4="$WORK_DIR/h4"
P4="$WORK_DIR/p4"
mkdir -p "$H4" "$P4"
seed_skills "$H4/.claude/skills" 80000 50
OUT4=$(run_hook "$H4" "$P4")
assert_warned "above hard threshold (80KB) emits [HARD]" "$OUT4" "[HARD] Cumulative skill description size"
assert_warned "hard warning mentions dropped-already wording" "$OUT4" "very likely already being silently dropped"

# ---------- Test 5: project scope also counted ----------
H5="$WORK_DIR/h5"
P5="$WORK_DIR/p5"
mkdir -p "$H5"
seed_skills "$P5/.claude/skills" 30000 15
OUT5=$(run_hook "$H5" "$P5")
assert_warned "project-scope skills counted toward total" "$OUT5" "[WARN] Cumulative skill description size"
assert_warned "project scope shows non-zero byte count" "$OUT5" "project scope (.claude/skills): 30"

# ---------- Test 6: user + project combine ----------
H6="$WORK_DIR/h6"
P6="$WORK_DIR/p6"
mkdir -p "$H6" "$P6"
seed_skills "$H6/.claude/skills" 15000 10
seed_skills "$P6/.claude/skills" 15000 10
OUT6=$(run_hook "$H6" "$P6")
assert_warned "user+project totals combine to cross threshold" "$OUT6" "cumulative total: 30000 bytes across 20 skills"

# ---------- Test 7: disable env var silences ----------
H7="$WORK_DIR/h7"
P7="$WORK_DIR/p7"
mkdir -p "$H7" "$P7"
seed_skills "$H7/.claude/skills" 80000 50
OUT7=$(run_hook "$H7" "$P7" "CC_SKILL_SIZE_DISABLE_WARNING=1")
assert_silent "CC_SKILL_SIZE_DISABLE_WARNING=1 silences output" "$OUT7"

# ---------- Test 8: custom warn threshold honored ----------
H8="$WORK_DIR/h8"
P8="$WORK_DIR/p8"
mkdir -p "$H8" "$P8"
seed_skills "$H8/.claude/skills" 10000 10
OUT8=$(run_hook "$H8" "$P8" "CC_SKILL_SIZE_WARN_BYTES=5000")
assert_warned "lowering warn threshold to 5KB triggers warning" "$OUT8" "[WARN]"

# ---------- Test 9: custom hard threshold honored ----------
H9="$WORK_DIR/h9"
P9="$WORK_DIR/p9"
mkdir -p "$H9" "$P9"
seed_skills "$H9/.claude/skills" 30000 30
OUT9=$(run_hook "$H9" "$P9" "CC_SKILL_SIZE_WARN_BYTES=10000 CC_SKILL_SIZE_HARD_BYTES=20000")
assert_warned "lowering hard threshold to 20KB triggers [HARD]" "$OUT9" "[HARD]"

# ---------- Test 10: 1MB / 200 skill stress ----------
H10="$WORK_DIR/h10"
P10="$WORK_DIR/p10"
mkdir -p "$H10" "$P10"
seed_skills "$H10/.claude/skills" 1000000 200
OUT10=$(run_hook "$H10" "$P10")
assert_warned "1MB / 200 skills emits [HARD]" "$OUT10" "[HARD]"
run_hook_exit "$H10" "$P10"
assert_exit_zero "stress test still advisory" $?

# ---------- Test 11: issue reference present ----------
H11="$WORK_DIR/h11"
P11="$WORK_DIR/p11"
mkdir -p "$H11" "$P11"
seed_skills "$H11/.claude/skills" 30000 30
OUT11=$(run_hook "$H11" "$P11")
assert_warned "warning text references issue 59921" "$OUT11" "Issue #59921"
assert_warned "warning text references /skills command" "$OUT11" "Run /skills"
assert_warned "warning text references suppression env var" "$OUT11" "CC_SKILL_SIZE_DISABLE_WARNING=1"

echo ""
echo "============================================"
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "============================================"
exit $FAIL
