#!/bin/bash
# test-before-push.sh — Block git push when tests haven't passed
#
# Solves: Claude pushing code that hasn't been tested (#36970)
#
# Checks for a test result marker file. If tests haven't been run
# (or failed), blocks the push.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "if": "Bash(git push *)",
#         "command": "~/.claude/hooks/test-before-push.sh"
#       }]
#     }]
#   }
# }
#
# The "if" field (v2.1.85+) eliminates process spawning for non-push commands.
# Without "if", the hook still works — it checks internally and exits early.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-test-before-push-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [test-before-push]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check git push commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+push\b'; then
    exit 0
fi

# Skip if no test framework is detected
HAS_TESTS=0
[ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null && HAS_TESTS=1
[ -f "pytest.ini" ] || [ -f "pyproject.toml" ] && HAS_TESTS=1
[ -f "Makefile" ] && grep -q "^test:" Makefile 2>/dev/null && HAS_TESTS=1

if (( HAS_TESTS == 0 )); then
    exit 0  # No test framework detected, allow push
fi

# Check for test result marker
MARKER="/tmp/cc-tests-passed-$(pwd | md5sum | cut -c1-8)"
if [ -f "$MARKER" ]; then
    # Tests passed within the last hour
    MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
    if (( MARKER_AGE < 3600 )); then
        exit 0  # Tests passed recently
    fi
fi

echo "BLOCKED: Run tests before pushing." >&2
echo "Tests haven't been run (or results are stale)." >&2
echo "" >&2
echo "Run your test suite, then try pushing again." >&2
echo "The test runner should create: $MARKER" >&2
exit 2
