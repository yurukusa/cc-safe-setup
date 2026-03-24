#!/bin/bash
# ================================================================
# verify-before-done.sh — Warn when committing without running tests
# ================================================================
# PURPOSE:
#   Claude Code often declares fixes "done" and commits without
#   verifying the fix actually works. This hook warns when a commit
#   is made in a project that has tests, but no test command was
#   run recently in the session.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Born from: https://github.com/anthropics/claude-code/issues/37818
#   "Claude repeatedly declares fixes done without verification"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check on git commit
echo "$COMMAND" | grep -qE '^\s*git\s+commit' || exit 0

# Track test execution via state file
STATE="/tmp/cc-tests-ran-$(pwd | md5sum | cut -c1-8)"

# Check if tests were run in this session
if [ ! -f "$STATE" ]; then
    # Detect if project has tests
    HAS_TESTS=0
    [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null && HAS_TESTS=1
    [ -f "pytest.ini" ] || [ -f "setup.cfg" ] || [ -f "pyproject.toml" ] && HAS_TESTS=1
    [ -f "Cargo.toml" ] && HAS_TESTS=1
    [ -f "go.mod" ] && HAS_TESTS=1
    [ -f "Makefile" ] && grep -q 'test:' Makefile 2>/dev/null && HAS_TESTS=1

    if [ "$HAS_TESTS" -eq 1 ]; then
        echo "WARNING: Committing without running tests first." >&2
        echo "Run your test suite before committing to verify changes work." >&2
        echo "To suppress: touch $STATE" >&2
    fi
fi

exit 0
