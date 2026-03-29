#!/bin/bash
# test-exit-code-verify.sh — Verify test command exit codes match results
#
# Problem: Claude reports "tests passed" even when they didn't run or failed.
# This PostToolUse hook checks the actual exit code of test commands and
# emits a warning if the exit code indicates failure.
#
# GitHub Issue: #1501 (Claude reports false test results)
#
# Usage: Add to settings.json as a PostToolUse hook on "Bash"
#
# How it works:
# 1. Detects test-like commands (npm test, pytest, jest, go test, etc.)
# 2. Checks the actual exit code from tool output
# 3. If exit code != 0, warns Claude via stderr so it cannot claim success
# 4. If no output was captured, warns about phantom test runs
#
# Why stderr: PostToolUse hook stderr is shown to Claude as feedback.
# This forces Claude to acknowledge test failures instead of fabricating results.
#
# TRIGGER: PostToolUse  MATCHER: "Bash"

INPUT=$(cat)

# Extract command and exit code
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exitCode // .tool_result.exit_code // empty' 2>/dev/null)
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Detect test commands
is_test_command() {
    local cmd="$1"
    echo "$cmd" | grep -qiE '(npm\s+test|npx\s+jest|npx\s+vitest|pytest|python\s+-m\s+pytest|go\s+test|cargo\s+test|bundle\s+exec\s+rspec|mix\s+test|dotnet\s+test|mvn\s+test|gradle\s+test|make\s+test|bash\s+test\.sh)'
}

if ! is_test_command "$COMMAND"; then
    exit 0
fi

# Check exit code
if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ]; then
    echo "⚠️ TEST FAILURE DETECTED" >&2
    echo "Command: $(echo "$COMMAND" | head -c 100)" >&2
    echo "Exit code: $EXIT_CODE" >&2
    echo "Do NOT report these tests as passing. The exit code proves failure." >&2
    echo "Re-read the output above and fix the failing tests." >&2
    exit 0
fi

# Check for empty output (phantom test run)
if [ -z "$STDOUT" ] || [ ${#STDOUT} -lt 10 ]; then
    echo "⚠️ TEST OUTPUT SUSPICIOUSLY SHORT" >&2
    echo "Command: $(echo "$COMMAND" | head -c 100)" >&2
    echo "Output length: ${#STDOUT} chars" >&2
    echo "Verify tests actually ran. Short output may indicate no tests executed." >&2
    exit 0
fi

# Tests appear to have run and passed
exit 0
