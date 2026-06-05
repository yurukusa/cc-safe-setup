#!/bin/bash
# Tests for verify-after-publish-reminder.sh
# Run: bash tests/test-verify-after-publish-reminder.sh
set -euo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/verify-after-publish-reminder.sh"

# Test exit code (this hook is always non-blocking: exit 0)
test_hook() {
    local input="$1" expected_exit="$2" desc="$3"
    local actual_exit=0
    echo "$input" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

# Test that stderr contains expected reminder text
test_hook_stderr() {
    local input="$1" pattern="$2" desc="$3"
    local stderr
    stderr=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null) || true
    if echo "$stderr" | grep -qE "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (pattern not found: $pattern)"
        echo "         got stderr: $(echo "$stderr" | head -2)"
        FAIL=$((FAIL + 1))
    fi
}

# Test that stderr does NOT contain reminder (silent pass)
test_hook_silent() {
    local input="$1" desc="$2"
    local stderr
    stderr=$(echo "$input" | bash "$HOOK" 2>&1 >/dev/null) || true
    if [ -z "$stderr" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected silent, got: $(echo "$stderr" | head -1))"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== verify-after-publish-reminder.sh tests ==="

# --- Exit code: always 0 (non-blocking) ---
test_hook '{"tool_input": {"command": "git push origin main"}}' 0 "git push: exit 0 (non-blocking)"
test_hook '{"tool_input": {"command": "ls -la"}}' 0 "non-publish command: exit 0"
test_hook '{}' 0 "empty input: exit 0"
test_hook '{"tool_input": {"command": ""}}' 0 "empty command: exit 0"

# --- Detection: publish commands trigger reminder ---
test_hook_stderr \
    '{"tool_input": {"command": "git push origin main"}}' \
    "verify-after-publish-reminder" \
    "git push triggers reminder"

test_hook_stderr \
    '{"tool_input": {"command": "git push origin main"}}' \
    "git remote" \
    "git push identifies platform as git remote"

test_hook_stderr \
    '{"tool_input": {"command": "hashnode-publish article.md"}}' \
    "Hashnode" \
    "hashnode-publish identifies Hashnode"

test_hook_stderr \
    '{"tool_input": {"command": "qiita-post --title foo --body bar"}}' \
    "Qiita" \
    "qiita-post identifies Qiita"

test_hook_stderr \
    '{"tool_input": {"command": "zenn-update --slug abc123"}}' \
    "Zenn" \
    "zenn-update identifies Zenn"

test_hook_stderr \
    '{"tool_input": {"command": "cd ~/projects/zenn-cc-book && git push"}}' \
    "verify-after-publish-reminder" \
    "git push from zenn-cc-book repo triggers reminder"

test_hook_stderr \
    '{"tool_input": {"command": "hatena-post --entry foo.md"}}' \
    "hatena" \
    "hatena-post identifies hatena"

test_hook_stderr \
    '{"tool_input": {"command": "tweet-post --text \"hello\""}}' \
    "X" \
    "tweet-post identifies X (Twitter)"

test_hook_stderr \
    '{"tool_input": {"command": "npm publish"}}' \
    "npm" \
    "npm publish identifies npm"

test_hook_stderr \
    '{"tool_input": {"command": "cargo publish"}}' \
    "crates.io" \
    "cargo publish identifies crates.io"

test_hook_stderr \
    '{"tool_input": {"command": "twine upload dist/*"}}' \
    "PyPI" \
    "twine upload identifies PyPI"

test_hook_stderr \
    '{"tool_input": {"command": "gh release create v1.0.0 --notes \"first\""}}' \
    "GitHub Release" \
    "gh release create identifies GitHub Release"

test_hook_stderr \
    '{"tool_input": {"command": "cdp-bridge eval \"document.querySelector(button).click()\" # Save changes"}}' \
    "dashboard" \
    "cdp-bridge Save changes identifies dashboard"

# --- Reminder content: includes verification guidance ---
test_hook_stderr \
    '{"tool_input": {"command": "git push origin main"}}' \
    "verify the persisted state" \
    "reminder mentions verifying persisted state"

test_hook_stderr \
    '{"tool_input": {"command": "git push origin main"}}' \
    "Re-fetch the public URL" \
    "reminder mentions URL re-fetch"

test_hook_stderr \
    '{"tool_input": {"command": "git push origin main"}}' \
    "Rate-limit" \
    "reminder mentions rate-limit failure mode"

test_hook_stderr \
    '{"tool_input": {"command": "git push origin main"}}' \
    "React-controlled input" \
    "reminder mentions React-controlled input failure mode"

# --- Negative cases: non-publish commands do NOT trigger reminder ---
test_hook_silent \
    '{"tool_input": {"command": "ls -la /tmp"}}' \
    "ls command: silent"

test_hook_silent \
    '{"tool_input": {"command": "git status"}}' \
    "git status: silent (no push)"

test_hook_silent \
    '{"tool_input": {"command": "git pull origin main"}}' \
    "git pull: silent (no push)"

test_hook_silent \
    '{"tool_input": {"command": "cat README.md"}}' \
    "cat command: silent"

test_hook_silent \
    '{"tool_input": {"command": "echo hello"}}' \
    "echo command: silent"

# --- Disable env: CC_PUBLISH_VERIFY_DISABLE=1 ---
ACTUAL_STDERR=$(echo '{"tool_input": {"command": "git push origin main"}}' | CC_PUBLISH_VERIFY_DISABLE=1 bash "$HOOK" 2>&1 >/dev/null || true)
if [ -z "$ACTUAL_STDERR" ]; then
    echo "  PASS: CC_PUBLISH_VERIFY_DISABLE=1 suppresses reminder"
    PASS=$((PASS + 1))
else
    echo "  FAIL: CC_PUBLISH_VERIFY_DISABLE=1 did not suppress reminder"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Total: $((PASS + FAIL)) | Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
