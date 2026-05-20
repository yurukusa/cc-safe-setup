#!/bin/bash
# Tests for skill-truncation-detector.sh
#
# Verifies the SessionStart-hook behavior for v2.1.144's silent removal
# of the Skill-listing truncation startup notification.

set -uo pipefail

HOOK="$(dirname "$0")/../examples/skill-truncation-detector.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Build an isolated test environment in /tmp so we don't touch the real
# ~/.claude/skills directory.
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

mk_skill() {
    local dir="$1"
    local name="$2"
    local has_frontmatter="${3:-yes}"
    mkdir -p "$dir"
    if [ "$has_frontmatter" = "yes" ]; then
        cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: Test skill $name
---
# $name
EOF
    else
        cat > "$dir/SKILL.md" <<EOF
# $name
Skill body without frontmatter.
EOF
    fi
}

run_hook() {
    local skills_dir="$1"
    local threshold="${2:-80}"
    local session_id="${3:-test-session-$RANDOM}"
    local extra_env="${4:-}"
    echo "{\"session_id\":\"$session_id\"}" \
        | env CC_SKILL_COUNT_THRESHOLD="$threshold" \
              CC_SKILL_DIRS="$skills_dir" \
              HOME="$TEST_ROOT" \
              $extra_env \
              bash "$HOOK" 2>&1
}

echo "=== skill-truncation-detector.sh tests ==="

# --- Test 1: no skills directory → exit 0 silent ---
output=$(run_hook "$TEST_ROOT/empty-skills")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "no skills directory → exit 0 silent"
else
    assert_fail "expected exit 0 silent, got rc=$rc output=$output"
fi

# --- Test 2: 3 well-formed skills, no issues → exit 0 silent ---
SD1="$TEST_ROOT/t2/skills"
mk_skill "$SD1/a" "skill-a"
mk_skill "$SD1/b" "skill-b"
mk_skill "$SD1/c" "skill-c"
output=$(run_hook "$SD1" 80 "test2")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "3 well-formed skills, no issues → exit 0 silent"
else
    assert_fail "expected exit 0 silent, got rc=$rc output=$output"
fi

# --- Test 3: skill count above threshold → warns ---
SD3="$TEST_ROOT/t3/skills"
for i in $(seq 1 5); do
    mk_skill "$SD3/skill-$i" "skill-$i"
done
output=$(run_hook "$SD3" 3 "test3")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "Skill count is 5"; then
    assert_pass "warns when skill count exceeds threshold"
else
    assert_fail "expected count warning, got rc=$rc output=$output"
fi

# --- Test 4: exact threshold count → warns (>= threshold) ---
SD4="$TEST_ROOT/t4/skills"
for i in $(seq 1 3); do
    mk_skill "$SD4/skill-$i" "skill-$i"
done
output=$(run_hook "$SD4" 3 "test4")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "Skill count is 3"; then
    assert_pass "warns at exact threshold (>= comparison)"
else
    assert_fail "expected warning at exact threshold, got rc=$rc"
fi

# --- Test 5: name collision detected → warns ---
SD5="$TEST_ROOT/t5/skills"
mk_skill "$SD5/dir-a" "duplicate-name"
mk_skill "$SD5/dir-b" "duplicate-name"
mk_skill "$SD5/dir-c" "unique"
output=$(run_hook "$SD5" 80 "test5")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "NAME COLLISIONS" && echo "$output" | grep -q "duplicate-name"; then
    assert_pass "detects name collision"
else
    assert_fail "expected collision warning, got rc=$rc output=$output"
fi

# --- Test 6: malformed frontmatter (no name: field) → warns ---
SD6="$TEST_ROOT/t6/skills"
mk_skill "$SD6/skill-a" "skill-a"
mk_skill "$SD6/skill-b" "skill-b" no
output=$(run_hook "$SD6" 80 "test6")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "MALFORMED FRONTMATTER"; then
    assert_pass "detects malformed frontmatter (no name: field)"
else
    assert_fail "expected malformed warning, got rc=$rc"
fi

# --- Test 7: disable flag respected ---
SD7="$TEST_ROOT/t7/skills"
mk_skill "$SD7/dir-a" "name1"
mk_skill "$SD7/dir-b" "name1"  # collision
output=$(run_hook "$SD7" 80 "test7" "CC_SKILL_TRUNCATION_DISABLE=1")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "disable flag silences detection"
else
    assert_fail "expected silence with disable flag, got rc=$rc output=$output"
fi

# --- Test 8: multiple findings combined → single reminder ---
SD8="$TEST_ROOT/t8/skills"
for i in $(seq 1 4); do
    mk_skill "$SD8/skill-$i" "skill-$i"
done
mk_skill "$SD8/dup-a" "duplicate"
mk_skill "$SD8/dup-b" "duplicate"
mk_skill "$SD8/no-fm" "no-fm" no
output=$(run_hook "$SD8" 5 "test8")
rc=$?
# Should fire for count (7 = 4 + 2 + 1 >= 5) + collision (duplicate) + malformed (no-fm)
if [ "$rc" -eq 0 ] && \
   echo "$output" | grep -q "Skill count is 7" && \
   echo "$output" | grep -q "NAME COLLISIONS" && \
   echo "$output" | grep -q "MALFORMED FRONTMATTER"; then
    assert_pass "combines count + collision + malformed into single reminder"
else
    assert_fail "expected combined warning, got rc=$rc output=$output"
fi

# --- Test 9: session-once behavior (second run silent) ---
SD9="$TEST_ROOT/t9/skills"
for i in $(seq 1 5); do
    mk_skill "$SD9/skill-$i" "skill-$i"
done
# First run: should warn
out1=$(run_hook "$SD9" 3 "session-9")
# Second run with same session_id: should be silent
out2=$(run_hook "$SD9" 3 "session-9")
if echo "$out1" | grep -q "Skill count" && [ -z "$out2" ]; then
    assert_pass "session-once: same session_id silent on second call"
else
    assert_fail "expected session-once behavior, got out1=$out1 out2=$out2"
fi

# --- Test 10: missing session_id → uses fallback, still works ---
SD10="$TEST_ROOT/t10/skills"
for i in $(seq 1 3); do
    mk_skill "$SD10/skill-$i" "skill-$i"
done
output=$(echo '{}' | env CC_SKILL_COUNT_THRESHOLD=2 CC_SKILL_DIRS="$SD10" HOME="$TEST_ROOT" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "Skill count is 3"; then
    assert_pass "missing session_id falls back gracefully and still detects"
else
    assert_fail "expected detection with missing session_id, got rc=$rc output=$output"
fi

# --- Test 11: empty input → still works ---
# Use a unique HOME so the per-session marker doesn't collide with test 10
# (which also uses fallback session_id "unknown-<seconds>").
SD11="$TEST_ROOT/t11/skills"
T11_HOME="$TEST_ROOT/t11/home"
mkdir -p "$T11_HOME"
for i in $(seq 1 4); do
    mk_skill "$SD11/skill-$i" "skill-$i"
done
output=$(printf '' | env CC_SKILL_COUNT_THRESHOLD=3 CC_SKILL_DIRS="$SD11" HOME="$T11_HOME" bash "$HOOK" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "Skill count is 4"; then
    assert_pass "empty input still triggers detection"
else
    assert_fail "expected detection with empty input, got rc=$rc output=$output"
fi

# --- Test 12: multiple skill directories via colon-separated list ---
SD12a="$TEST_ROOT/t12/skills-a"
SD12b="$TEST_ROOT/t12/skills-b"
mk_skill "$SD12a/x" "from-a"
mk_skill "$SD12b/y" "from-b"
mk_skill "$SD12b/z" "from-b"  # collision across dirs
output=$(run_hook "$SD12a:$SD12b" 80 "test12")
rc=$?
if [ "$rc" -eq 0 ] && echo "$output" | grep -q "from-b"; then
    assert_pass "supports multiple skill directories (colon-separated)"
else
    assert_fail "expected multi-dir detection, got rc=$rc output=$output"
fi

# --- Test 13: SessionStart hook should NOT exit 2 (non-blocking) ---
SD13="$TEST_ROOT/t13/skills"
for i in $(seq 1 5); do
    mk_skill "$SD13/skill-$i" "skill-$i"
done
output=$(run_hook "$SD13" 3 "test13")
rc=$?
if [ "$rc" -eq 0 ]; then
    assert_pass "always exits 0 (SessionStart hooks should not block)"
else
    assert_fail "expected exit 0 (non-blocking), got rc=$rc"
fi

# --- Test 14: skills with quotes/spaces in name handled ---
SD14="$TEST_ROOT/t14/skills"
mkdir -p "$SD14/quoted"
cat > "$SD14/quoted/SKILL.md" <<'EOF'
---
name: "quoted-name"
description: A skill with quoted name in YAML
---
EOF
mkdir -p "$SD14/spaced"
cat > "$SD14/spaced/SKILL.md" <<'EOF'
---
name:    spaced-with-leading-whitespace
description: Test
---
EOF
output=$(run_hook "$SD14" 80 "test14")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$output" ]; then
    assert_pass "handles quoted names and leading whitespace correctly"
else
    assert_fail "expected silence for clean skills, got rc=$rc output=$output"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
