#!/bin/bash
# Tests for subscription-bypass-detector.sh
# Run: bash tests/test-subscription-bypass-detector.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/subscription-bypass-detector.sh"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

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

assert_silent() {
    local label="$1"
    local output="$2"
    if [ -z "$output" ]; then
        PASS=$((PASS + 1))
        echo "  ✓ $label"
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label"
        echo "    expected silent, got: ${output:0:200}"
    fi
}

assert_emits_warning() {
    local label="$1"
    local output="$2"
    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        local ctx
        ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
        if echo "$ctx" | grep -q "ANTHROPIC_API_KEY detected"; then
            PASS=$((PASS + 1))
            echo "  ✓ $label"
        else
            FAIL=$((FAIL + 1))
            echo "  ✗ $label (warning text not as expected)"
            echo "    got context start: ${ctx:0:200}"
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label (no hookSpecificOutput)"
        echo "    got: ${output:0:200}"
    fi
}

assert_source_in_warning() {
    local label="$1"
    local output="$2"
    local expected_substr="$3"
    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        local ctx
        ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
        if echo "$ctx" | grep -qF "$expected_substr"; then
            PASS=$((PASS + 1))
            echo "  ✓ $label"
        else
            FAIL=$((FAIL + 1))
            echo "  ✗ $label (source not surfaced)"
            echo "    expected substring: $expected_substr"
            echo "    got: ${ctx:0:400}"
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  ✗ $label (no output)"
    fi
}

echo "=== Silent cases (no API key in env, no dotenv) ==="

H1="$WORK_DIR/home1"
mkdir -p "$H1" "$H1/.claude"
OUT=$(run_hook "$H1" "$H1")
assert_silent "no env, no dotenv files" "$OUT"

# Empty dotenv files
touch "$H1/.env"
touch "$H1/.claude/.env"
OUT=$(run_hook "$H1" "$H1")
assert_silent "empty dotenv files" "$OUT"

# Dotenv has other keys but not ANTHROPIC_API_KEY
echo "OTHER_KEY=value" > "$H1/.env"
echo "FOO=bar" > "$H1/.claude/.env"
OUT=$(run_hook "$H1" "$H1")
assert_silent "dotenv with unrelated keys only" "$OUT"

echo ""
echo "=== Detection cases ==="

# Process env has ANTHROPIC_API_KEY
H2="$WORK_DIR/home2"
mkdir -p "$H2"
OUT=$(run_hook "$H2" "$H2" "ANTHROPIC_API_KEY=sk-test-123")
assert_emits_warning "ANTHROPIC_API_KEY in process env" "$OUT"
assert_source_in_warning "process env source surfaced" "$OUT" "process environment"

# ~/.claude/.env has ANTHROPIC_API_KEY
H3="$WORK_DIR/home3"
mkdir -p "$H3/.claude"
echo "ANTHROPIC_API_KEY=sk-test-456" > "$H3/.claude/.env"
OUT=$(run_hook "$H3" "$H3")
assert_emits_warning "ANTHROPIC_API_KEY in ~/.claude/.env" "$OUT"
assert_source_in_warning "Claude dotenv source surfaced" "$OUT" "Claude per-user dotenv"

# $HOME/.env has ANTHROPIC_API_KEY
H4="$WORK_DIR/home4"
mkdir -p "$H4"
echo "ANTHROPIC_API_KEY=sk-test-789" > "$H4/.env"
OUT=$(run_hook "$H4" "$H4")
assert_emits_warning "ANTHROPIC_API_KEY in ~/.env" "$OUT"
assert_source_in_warning "home dotenv source surfaced" "$OUT" "user home dotenv"

# project .env (PWD) has ANTHROPIC_API_KEY
H5="$WORK_DIR/home5"
P5="$WORK_DIR/proj5"
mkdir -p "$H5" "$P5"
echo "ANTHROPIC_API_KEY=sk-test-pwd" > "$P5/.env"
OUT=$(run_hook "$H5" "$P5")
assert_emits_warning "ANTHROPIC_API_KEY in project .env" "$OUT"
assert_source_in_warning "project dotenv source surfaced" "$OUT" "project working-directory dotenv"

echo ""
echo "=== Whitespace handling ==="

# With leading whitespace and quoted value
H6="$WORK_DIR/home6"
mkdir -p "$H6/.claude"
cat > "$H6/.claude/.env" <<EOF
  ANTHROPIC_API_KEY = "sk-quoted"
OTHER=ignored
EOF
OUT=$(run_hook "$H6" "$H6")
assert_emits_warning "ANTHROPIC_API_KEY with whitespace and quotes" "$OUT"

# Commented out line should be silent
H7="$WORK_DIR/home7"
mkdir -p "$H7/.claude"
cat > "$H7/.claude/.env" <<EOF
# ANTHROPIC_API_KEY=sk-commented-out
OTHER=value
EOF
OUT=$(run_hook "$H7" "$H7")
assert_silent "commented-out ANTHROPIC_API_KEY (silent)" "$OUT"

echo ""
echo "=== Multiple source detection ==="

H8="$WORK_DIR/home8"
P8="$WORK_DIR/proj8"
mkdir -p "$H8/.claude" "$P8"
echo "ANTHROPIC_API_KEY=sk-from-claude-env" > "$H8/.claude/.env"
echo "ANTHROPIC_API_KEY=sk-from-pwd-env" > "$P8/.env"
OUT=$(run_hook "$H8" "$P8" "ANTHROPIC_API_KEY=sk-from-process")
assert_emits_warning "multiple sources detected" "$OUT"
# Should mention all three
assert_source_in_warning "process env in multi" "$OUT" "process environment"
assert_source_in_warning "Claude dotenv in multi" "$OUT" "Claude per-user dotenv"
assert_source_in_warning "project dotenv in multi" "$OUT" "project working-directory dotenv"

echo ""
echo "=== Configuration: disable and acknowledge ==="

H9="$WORK_DIR/home9"
mkdir -p "$H9"
OUT=$(run_hook "$H9" "$H9" "ANTHROPIC_API_KEY=sk-test CC_SUBSCRIPTION_BYPASS_DISABLE=1")
assert_silent "CC_SUBSCRIPTION_BYPASS_DISABLE=1 silences output" "$OUT"

OUT=$(run_hook "$H9" "$H9" "ANTHROPIC_API_KEY=sk-test CC_SUBSCRIPTION_BYPASS_ACK=1")
assert_silent "CC_SUBSCRIPTION_BYPASS_ACK=1 suppresses warning (intended use)" "$OUT"

# Logging
LOG_FILE="$WORK_DIR/log.txt"
OUT=$(run_hook "$H9" "$H9" "ANTHROPIC_API_KEY=sk-test CC_SUBSCRIPTION_BYPASS_LOG=$LOG_FILE")
assert_emits_warning "logging enabled still emits warning" "$OUT"
if grep -q "subscription-bypass-detected" "$LOG_FILE" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ log file contains detection event"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ log file missing detection event"
fi

# ACK + LOG together: silent warning but log entry recorded
LOG_FILE2="$WORK_DIR/log2.txt"
OUT=$(run_hook "$H9" "$H9" "ANTHROPIC_API_KEY=sk-test CC_SUBSCRIPTION_BYPASS_ACK=1 CC_SUBSCRIPTION_BYPASS_LOG=$LOG_FILE2")
assert_silent "ACK suppresses warning" "$OUT"
if grep -q "subscription-bypass-detected" "$LOG_FILE2" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  ✓ ACK still produces log entry (as documented)"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ ACK did not log entry"
fi

echo ""
echo "=== JSON structure ==="

H10="$WORK_DIR/home10"
mkdir -p "$H10"
OUT=$(run_hook "$H10" "$H10" "ANTHROPIC_API_KEY=sk-test")
if echo "$OUT" | jq -e '.' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  ✓ output is valid JSON"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ output is not valid JSON: ${OUT:0:200}"
fi

HOOK_NAME=$(echo "$OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
if [ "$HOOK_NAME" = "SessionStart" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ hookEventName is SessionStart"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ hookEventName missing or wrong: $HOOK_NAME"
fi

# Check Issue #60093 reference appears in context
CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty')
if echo "$CTX" | grep -q "60093"; then
    PASS=$((PASS + 1))
    echo "  ✓ context references Issue #60093"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ context missing Issue #60093 reference"
fi

if echo "$CTX" | grep -q "1,050"; then
    PASS=$((PASS + 1))
    echo "  ✓ context references the USD 1,050 case"
else
    FAIL=$((FAIL + 1))
    echo "  ✗ context missing 1,050 reference"
fi

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))   PASS: $PASS   FAIL: $FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
