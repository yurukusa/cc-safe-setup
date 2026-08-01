#!/bin/bash
# no-push-without-tests.sh — Block git push if tests haven't been run
#
# Prevents: Pushing untested code that breaks CI.
#           Checks if test command was run in the current session.
#
# Tracks test runs via a marker file.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-push-without-tests-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-push-without-tests]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

MARKER="/tmp/cc-tests-ran-$$"

# Track test runs
if echo "$COMMAND" | grep -qiE '(npm\s+test|npx\s+(jest|vitest)|pytest|go\s+test|cargo\s+test|make\s+test|bash\s+test)'; then
  touch "$MARKER"
  exit 0
fi

# Check before push
if echo "$COMMAND" | grep -qE '^\s*git\s+push'; then
  if [ ! -f "$MARKER" ]; then
    echo "WARNING: No tests have been run in this session." >&2
    echo "  Run tests before pushing to avoid CI failures." >&2
    # Warning only. Change exit 0 to exit 2 to enforce.
  fi
fi

exit 0
