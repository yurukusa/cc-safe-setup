#!/bin/bash
# ================================================================
# test-coverage-guard.sh — Warn when code grows without tests
# ================================================================
# PURPOSE:
#   Claude adds features without writing tests. This hook checks
#   if source files changed more than test files, suggesting tests
#   are needed before committing.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Count staged source vs test file changes
SRC_CHANGES=$(git diff --cached --name-only 2>/dev/null | grep -cvE '(test|spec|__tests__|_test\.|\.test\.)' || echo 0)
TEST_CHANGES=$(git diff --cached --name-only 2>/dev/null | grep -cE '(test|spec|__tests__|_test\.|\.test\.)' || echo 0)

# If source changed significantly but no tests
if [ "$SRC_CHANGES" -gt 3 ] && [ "$TEST_CHANGES" -eq 0 ]; then
    echo "WARNING: $SRC_CHANGES source files changed but 0 test files." >&2
    echo "Consider adding tests for the new code." >&2
fi

exit 0
