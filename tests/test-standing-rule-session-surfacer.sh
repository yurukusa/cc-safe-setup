#!/bin/bash
# Tests for standing-rule-session-surfacer.sh
# Hook addresses issue #59944 (auto-memory rule loaded but not enforced).
set -euo pipefail

HOOK="$(dirname "$0")/../examples/standing-rule-session-surfacer.sh"
PASS=0
FAIL=0

# Create a temp memory directory with various test fixtures.
TMP_MEMORY=$(mktemp -d /tmp/test-standing-rule.XXXXXX)
trap 'rm -rf "$TMP_MEMORY"' EXIT

# --- Test 1: empty memory dir produces no output ---
mkdir -p "$TMP_MEMORY/empty"
output=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/empty" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: empty memory dir produces no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: empty dir should produce no output, got: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: memory file with no rule markers produces no output ---
mkdir -p "$TMP_MEMORY/no-rules"
cat > "$TMP_MEMORY/no-rules/notes.md" <<'EOF'
# Just some notes
- Random observation
- A small thought
- No standing rules here
EOF
output=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/no-rules" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: file with no markers produces no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: no-markers file should produce no output, got: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: memory file with STANDING RULE produces JSON output ---
mkdir -p "$TMP_MEMORY/with-rule"
cat > "$TMP_MEMORY/with-rule/feedback.md" <<'EOF'
# Operator feedback

STANDING RULE: every problem/feature → loop dlog+screenshot+cliclick+analyze+correct
Do NOT bounce verification to user as default.

Marked third strike because I had to add it after two prior incidents.
EOF
output=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/with-rule" bash "$HOOK")
if echo "$output" | grep -q "STANDING RULE"; then
    echo "  PASS: STANDING RULE marker is surfaced"
    PASS=$((PASS + 1))
else
    echo "  FAIL: STANDING RULE not in output: $output"
    FAIL=$((FAIL + 1))
fi

if echo "$output" | grep -q "third strike"; then
    echo "  PASS: third strike marker is surfaced"
    PASS=$((PASS + 1))
else
    echo "  FAIL: third strike not in output"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: JSON output is valid and has hookSpecificOutput ---
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null 2>&1; then
    echo "  PASS: output is valid JSON with hookSpecificOutput.additionalContext"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output not valid hookSpecificOutput JSON"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: hookEventName is SessionStart ---
event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // "MISSING"')
if [ "$event" = "SessionStart" ]; then
    echo "  PASS: hookEventName is SessionStart"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hookEventName should be SessionStart, got: $event"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Japanese markers (必ず / 絶対 / etc.) are surfaced ---
mkdir -p "$TMP_MEMORY/japanese"
cat > "$TMP_MEMORY/japanese/feedback-jp.md" <<'EOF'
# 日本語の規則

絶対ルール: 投稿の前に必ず手元の事実の確認を実行する。
ぐらすの指示なしで購入の頁の変更はやるな。
EOF
output=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/japanese" bash "$HOOK")
if echo "$output" | grep -q "絶対"; then
    echo "  PASS: Japanese 絶対 marker is surfaced"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Japanese 絶対 not in output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: MUST NOT and NEVER markers are surfaced ---
mkdir -p "$TMP_MEMORY/must-never"
cat > "$TMP_MEMORY/must-never/rules.md" <<'EOF'
# Hard rules

MUST NOT push to main without review.
NEVER do force push on shared branches.
ALWAYS do tests before commit.
EOF
output=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/must-never" bash "$HOOK")
if echo "$output" | grep -q "MUST NOT"; then
    echo "  PASS: MUST NOT marker is surfaced"
    PASS=$((PASS + 1))
else
    echo "  FAIL: MUST NOT not in output"
    FAIL=$((FAIL + 1))
fi

if echo "$output" | grep -q "NEVER do"; then
    echo "  PASS: NEVER do marker is surfaced"
    PASS=$((PASS + 1))
else
    echo "  FAIL: NEVER do not in output"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: MAX_LINES limit is enforced per file ---
mkdir -p "$TMP_MEMORY/many-rules"
cat > "$TMP_MEMORY/many-rules/many.md" <<'EOF'
STANDING RULE 1
STANDING RULE 2
STANDING RULE 3
STANDING RULE 4
STANDING RULE 5
STANDING RULE 6
STANDING RULE 7
STANDING RULE 8
STANDING RULE 9
STANDING RULE 10
STANDING RULE 11
STANDING RULE 12
EOF
output=$(echo '{}' | CC_STANDING_RULE_MAX_LINES=5 CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/many-rules" bash "$HOOK")
# Should surface 5 rules, not 12. JSON encodes newlines as \n, so extract
# the additionalContext string, decode, and count rule lines.
rules_count=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -cE '^[0-9]+:STANDING RULE [0-9]+' || true)
if [ "$rules_count" -eq 5 ]; then
    echo "  PASS: MAX_LINES limit honored (count=$rules_count, expected 5)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: MAX_LINES not honored, count=$rules_count (expected 5)"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: hook is idempotent (running twice produces same output) ---
mkdir -p "$TMP_MEMORY/idempotent"
cat > "$TMP_MEMORY/idempotent/r.md" <<'EOF'
STANDING RULE: keep things simple.
EOF
out1=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/idempotent" bash "$HOOK")
out2=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/idempotent" bash "$HOOK")
if [ "$out1" = "$out2" ]; then
    echo "  PASS: hook is idempotent"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook is not idempotent"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: non-existent memory dir is handled gracefully ---
output=$(echo '{}' | CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/does-not-exist" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: non-existent dir handled gracefully (empty output)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: non-existent dir produced unexpected output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: custom pattern is honored ---
mkdir -p "$TMP_MEMORY/custom-pattern"
cat > "$TMP_MEMORY/custom-pattern/feedback.md" <<'EOF'
CRITICAL: do not skip security checks.
INFO: this is just informational.
EOF
output=$(echo '{}' | CC_STANDING_RULE_PATTERN="CRITICAL" CC_STANDING_RULE_MEMORY_DIR="$TMP_MEMORY/custom-pattern" bash "$HOOK")
if echo "$output" | grep -q "CRITICAL"; then
    echo "  PASS: custom pattern (CRITICAL) is honored"
    PASS=$((PASS + 1))
else
    echo "  FAIL: custom pattern not honored"
    FAIL=$((FAIL + 1))
fi

# Verify INFO is NOT included when only CRITICAL is the pattern
if echo "$output" | grep -q "INFO: this is"; then
    echo "  FAIL: INFO should not be in output when pattern=CRITICAL"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: INFO correctly excluded when pattern=CRITICAL"
    PASS=$((PASS + 1))
fi

# --- Summary ---
echo ""
echo "=================================="
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "=================================="

[ "$FAIL" -eq 0 ]
