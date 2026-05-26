#!/bin/bash
# Tests for skills-settings-validator.sh
# Hook addresses issue #62421 (fabricated Skills-related settings fields).
set -u

HOOK="$(dirname "$0")/../examples/skills-settings-validator.sh"
PASS=0
FAIL=0

TMP=$(mktemp -d /tmp/test-skills-validator.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: no settings files produce no output ---
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/missing.json" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: missing settings file produces no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: missing file should produce no output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: empty JSON produces no output ---
echo '{}' > "$TMP/empty.json"
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/empty.json" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: empty JSON produces no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: empty JSON should produce no output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: valid schema fields produce no output ---
cat > "$TMP/valid.json" <<'EOF'
{
  "permissions": {"allow": [], "deny": []},
  "env": {"FOO": "bar"},
  "hooks": {}
}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/valid.json" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: valid schema fields produce no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: valid fields should produce no output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: disabledSkills (canonical fabrication) detected ---
cat > "$TMP/fab1.json" <<'EOF'
{
  "permissions": {"allow": []},
  "disabledSkills": ["mcp-builder", "pdf"]
}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab1.json" bash "$HOOK")
if echo "$output" | grep -q "disabledSkills"; then
    echo "  PASS: disabledSkills is flagged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: disabledSkills should be flagged. Output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: output is valid JSON ---
if echo "$output" | jq empty 2>/dev/null; then
    echo "  PASS: output is valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output is not valid JSON: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: output references issue #62421 ---
if echo "$output" | grep -q "62421"; then
    echo "  PASS: output references issue #62421"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output should reference issue #62421"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: output has hookSpecificOutput.additionalContext ---
context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [ -n "$context" ]; then
    echo "  PASS: output has hookSpecificOutput.additionalContext"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output missing hookSpecificOutput.additionalContext"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: enabledSkills also detected ---
cat > "$TMP/fab2.json" <<'EOF'
{"enabledSkills": ["only-this-one"]}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab2.json" bash "$HOOK")
if echo "$output" | grep -q "enabledSkills"; then
    echo "  PASS: enabledSkills is flagged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: enabledSkills should be flagged"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: skillsConfig also detected ---
cat > "$TMP/fab3.json" <<'EOF'
{"skillsConfig": {"defaultEnabled": false}}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab3.json" bash "$HOOK")
if echo "$output" | grep -q "skillsConfig"; then
    echo "  PASS: skillsConfig is flagged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: skillsConfig should be flagged"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: multiple fabricated fields all detected ---
cat > "$TMP/fab4.json" <<'EOF'
{
  "disabledSkills": [],
  "enabledSkills": [],
  "skillRouting": {}
}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab4.json" bash "$HOOK")
if echo "$output" | grep -q "disabledSkills" && \
   echo "$output" | grep -q "enabledSkills" && \
   echo "$output" | grep -q "skillRouting"; then
    echo "  PASS: multiple fabricated fields all flagged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: not all fabricated fields flagged. Output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: multiple files scanned ---
cat > "$TMP/fab5a.json" <<'EOF'
{"disabledSkills": []}
EOF
cat > "$TMP/fab5b.json" <<'EOF'
{"skillFilter": ""}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab5a.json:$TMP/fab5b.json" bash "$HOOK")
if echo "$output" | grep -q "disabledSkills" && \
   echo "$output" | grep -q "skillFilter"; then
    echo "  PASS: multiple files all scanned"
    PASS=$((PASS + 1))
else
    echo "  FAIL: multiple files not all scanned. Output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: file path included in findings ---
if echo "$output" | grep -q "fab5a.json" && \
   echo "$output" | grep -q "fab5b.json"; then
    echo "  PASS: file path included in findings"
    PASS=$((PASS + 1))
else
    echo "  FAIL: file path missing from findings"
    FAIL=$((FAIL + 1))
fi

# --- Test 13: invalid JSON file silently skipped ---
echo "not valid json" > "$TMP/broken.json"
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/broken.json" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: invalid JSON silently skipped"
    PASS=$((PASS + 1))
else
    echo "  FAIL: invalid JSON should be silently skipped: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 14: invalid + valid mix only flags the valid ---
cat > "$TMP/fab6.json" <<'EOF'
{"disabledSkills": []}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/broken.json:$TMP/fab6.json" bash "$HOOK")
if echo "$output" | grep -q "fab6.json: disabledSkills" && \
   ! echo "$output" | grep -q "broken.json"; then
    echo "  PASS: invalid skipped, valid flagged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: mix handling incorrect. Output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 15: extra patterns via env var detected ---
cat > "$TMP/fab7.json" <<'EOF'
{"customSkillField": "x"}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab7.json" CC_SKILLS_EXTRA_PATTERNS="customSkillField" bash "$HOOK")
if echo "$output" | grep -q "customSkillField"; then
    echo "  PASS: extra pattern via env var detected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: extra pattern not detected. Output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 16: extra patterns coexist with defaults ---
cat > "$TMP/fab8.json" <<'EOF'
{"disabledSkills": [], "myCustomField": "y"}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/fab8.json" CC_SKILLS_EXTRA_PATTERNS="myCustomField" bash "$HOOK")
if echo "$output" | grep -q "disabledSkills" && \
   echo "$output" | grep -q "myCustomField"; then
    echo "  PASS: extra patterns coexist with defaults"
    PASS=$((PASS + 1))
else
    echo "  FAIL: extra+default coexist failed. Output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 17: nested non-top-level skills key not flagged ---
cat > "$TMP/nested.json" <<'EOF'
{
  "permissions": {
    "allow": ["Skill(foo)"],
    "deny": []
  },
  "env": {"disabledSkills_unused": "1"}
}
EOF
output=$(echo '{}' | CC_SKILLS_SETTINGS_FILES="$TMP/nested.json" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: nested skills mentions are not flagged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: nested skills mentions should not be flagged: $output"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
[ "$FAIL" -eq 0 ]
