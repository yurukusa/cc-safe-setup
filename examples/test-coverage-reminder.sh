#!/bin/bash
# test-coverage-reminder.sh — Remind to run tests after code changes
#
# Prevents: Pushing untested code. Claude often edits files
#           without running the test suite afterward.
#
# Tracks: number of Edit/Write calls since last test run.
# Warns at: 5 edits without tests, blocks at 10.
#
# TRIGGER: PostToolUse
# MATCHER: "Write|Edit|Bash"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Edit|Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/test-coverage-reminder.sh" }]
#     }]
#   }
# }

COUNTER_FILE="/tmp/cc-edit-since-test-$$"
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

case "$TOOL" in
  Write|Edit)
    # Increment edit counter
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"

    if [ "$COUNT" -eq 5 ]; then
      echo "REMINDER: 5 files changed since last test run. Consider running tests." >&2
    elif [ "$COUNT" -ge 10 ]; then
      echo "WARNING: $COUNT files changed without running tests. Run tests now." >&2
    fi
    ;;
  Bash)
    # Reset counter if a test command was run
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$CMD" | grep -qiE '(npm\s+test|npx\s+jest|npx\s+vitest|pytest|go\s+test|cargo\s+test|make\s+test|bash\s+test)'; then
      echo "0" > "$COUNTER_FILE"
    fi
    ;;
esac

exit 0
