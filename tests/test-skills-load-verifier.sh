set -u
HOOK="$(dirname "$0")/../examples/skills-load-verifier.sh"
PASS=0
FAIL=0
TMP=$(mktemp -d /tmp/test-skills-load.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
assert_no_output() {
    local desc="$1"
    local output="$2"
    if [ -z "$output" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — unexpected output: $output"
        FAIL=$((FAIL + 1))
    fi
}
assert_contains() {
    local desc="$1"
    local output="$2"
    local needle="$3"
    if echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output: $output"
        FAIL=$((FAIL + 1))
    fi
}
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/missing" bash "$HOOK")
assert_no_output "missing skills directory produces no output" "$output"
mkdir -p "$TMP/empty-skills"
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/empty-skills" bash "$HOOK")
assert_no_output "empty skills directory produces no output" "$output"
mkdir -p "$TMP/valid-root/my-skill"
cat > "$TMP/valid-root/my-skill/SKILL.md" << 'EOF'
---
name: my-skill
description: A valid skill with proper frontmatter for testing purposes
---
This is the body of the skill.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/valid-root" bash "$HOOK")
assert_no_output "valid skill produces no output" "$output"
mkdir -p "$TMP/missing-md-root/broken-skill"
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/missing-md-root" bash "$HOOK")
assert_contains "missing SKILL.md detected" "$output" "missing SKILL.md"
mkdir -p "$TMP/no-fm-root/no-fm-skill"
cat > "$TMP/no-fm-root/no-fm-skill/SKILL.md" << 'EOF'
This skill has no frontmatter at all.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/no-fm-root" bash "$HOOK")
assert_contains "missing frontmatter detected" "$output" "missing YAML frontmatter"
mkdir -p "$TMP/empty-fm-root/empty-fm-skill"
cat > "$TMP/empty-fm-root/empty-fm-skill/SKILL.md" << 'EOF'
---
---
Body without frontmatter content.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/empty-fm-root" bash "$HOOK")
assert_contains "empty frontmatter detected" "$output" "empty or unterminated frontmatter"
mkdir -p "$TMP/no-name-root/no-name-skill"
cat > "$TMP/no-name-root/no-name-skill/SKILL.md" << 'EOF'
---
description: This skill has a description but no name field
---
Body.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/no-name-root" bash "$HOOK")
assert_contains "missing name field detected" "$output" "missing or empty 'name' field"
mkdir -p "$TMP/no-desc-root/no-desc-skill"
cat > "$TMP/no-desc-root/no-desc-skill/SKILL.md" << 'EOF'
---
name: no-desc-skill
---
Body.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/no-desc-root" bash "$HOOK")
assert_contains "missing description field detected" "$output" "missing or empty 'description' field"
mkdir -p "$TMP/short-desc-root/short-desc-skill"
cat > "$TMP/short-desc-root/short-desc-skill/SKILL.md" << 'EOF'
---
name: short-desc-skill
description: short
---
Body.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/short-desc-root" bash "$HOOK")
assert_contains "short description detected" "$output" "too short"
mkdir -p "$TMP/mismatch-root/dir-name"
cat > "$TMP/mismatch-root/dir-name/SKILL.md" << 'EOF'
---
name: different-name
description: This skill has a name that does not match its directory name
---
Body.
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/mismatch-root" bash "$HOOK")
assert_contains "name/directory mismatch detected" "$output" "does not match directory name"
mkdir -p "$TMP/mixed-root/good"
cat > "$TMP/mixed-root/good/SKILL.md" << 'EOF'
---
name: good
description: A perfectly valid skill for the mixed test
---
EOF
mkdir -p "$TMP/mixed-root/bad"
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/mixed-root" bash "$HOOK")
assert_contains "mixed dir surfaces bad skill" "$output" "missing SKILL.md"
mkdir -p "$TMP/relax-root/relaxed-skill"
cat > "$TMP/relax-root/relaxed-skill/SKILL.md" << 'EOF'
---
name: relaxed-skill
description: short
---
EOF
output=$(echo '{}' | CC_SKILLS_MIN_DESC_LEN=3 CC_SKILLS_DIRS="$TMP/relax-root" bash "$HOOK")
assert_no_output "MIN_DESC_LEN override accepts short description" "$output"
mkdir -p "$TMP/quoted-root/quoted-skill"
cat > "$TMP/quoted-root/quoted-skill/SKILL.md" << 'EOF'
---
name: "quoted-skill"
description: "A skill with quoted frontmatter values"
---
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/quoted-root" bash "$HOOK")
assert_no_output "quoted name/description recognized as valid" "$output"
mkdir -p "$TMP/sq-root/sq-skill"
cat > "$TMP/sq-root/sq-skill/SKILL.md" << 'EOF'
---
name: 'sq-skill'
description: 'Single-quoted frontmatter values for testing'
---
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/sq-root" bash "$HOOK")
assert_no_output "single-quoted name/description recognized as valid" "$output"
mkdir -p "$TMP/multi-a/skill-a"
cat > "$TMP/multi-a/skill-a/SKILL.md" << 'EOF'
---
name: skill-a
description: First valid skill in directory A for the multi-dir test
---
EOF
mkdir -p "$TMP/multi-b/skill-b"
cat > "$TMP/multi-b/skill-b/SKILL.md" << 'EOF'
---
EOF
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/multi-a:$TMP/multi-b" bash "$HOOK")
assert_contains "multi-dir scan surfaces broken skill" "$output" "skill-b"
mkdir -p "$TMP/exit-test-root/broken"
echo '{}' | CC_SKILLS_DIRS="$TMP/exit-test-root" bash "$HOOK"
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    echo "  PASS: hook exits 0 even with findings (advisory only)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook should exit 0 even with findings, got $exit_code"
    FAIL=$((FAIL + 1))
fi
mkdir -p "$TMP/json-test-root/broken"
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/json-test-root" bash "$HOOK")
if echo "$output" | jq empty 2>/dev/null; then
    echo "  PASS: output is valid JSON when findings present"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output should be valid JSON: $output"
    FAIL=$((FAIL + 1))
fi
mkdir -p "$TMP/struct-test-root/broken"
output=$(echo '{}' | CC_SKILLS_DIRS="$TMP/struct-test-root" bash "$HOOK")
ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // empty')
if [ -n "$ctx" ]; then
    echo "  PASS: JSON has hookSpecificOutput.additionalContext field"
    PASS=$((PASS + 1))
else
    echo "  FAIL: JSON should have hookSpecificOutput.additionalContext: $output"
    FAIL=$((FAIL + 1))
fi
echo ""
echo "=============================="
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
