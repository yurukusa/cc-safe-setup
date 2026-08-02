#!/bin/bash
# push-requires-test-pass.sh — Block git push to main/production without test verification
#
# Solves: Agent pushes broken code to production without running tests
#         (#36673 — pushed broken code 4 times, crashed live SaaS application)
#
# How it works:
#   1. PostToolUse companion records when tests pass (creates state file)
#   2. This PreToolUse hook blocks git push to protected branches unless tests passed
#
# Requires companion hook: push-requires-test-pass-record.sh (PostToolUse)
#
# Usage: Add BOTH hooks to settings.json
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/push-requires-test-pass.sh" }]
#     }],
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/push-requires-test-pass-record.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-push-requires-test-pass-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [push-requires-test-pass]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only check git push commands
echo "$COMMAND" | grep -qE '^\s*git\s+push\b' || exit 0

# Protected branches
PROTECTED='main|master|production|prod|release|deploy'

# Check if pushing to a protected branch
if echo "$COMMAND" | grep -qE "git\s+push\s+\S+\s+($PROTECTED)\b|git\s+push\s+($PROTECTED)\b|git\s+push\s*$"; then
    STATE_FILE="/tmp/.cc-test-pass-$(pwd | md5sum | cut -c1-8)"

    if [ ! -f "$STATE_FILE" ]; then
        echo "BLOCKED: git push to protected branch without test verification" >&2
        echo "  Run your test suite first. Tests must pass before pushing." >&2
        echo "  Protected branches: main, master, production, prod, release, deploy" >&2
        exit 2
    fi

    # Check if test pass is recent (within last 30 minutes)
    if [ -f "$STATE_FILE" ]; then
        PASS_TIME=$(cat "$STATE_FILE" 2>/dev/null)
        NOW=$(date +%s)
        AGE=$(( NOW - PASS_TIME ))
        if [ "$AGE" -gt 1800 ]; then
            echo "BLOCKED: Test pass record is stale ($(( AGE / 60 )) minutes old)" >&2
            echo "  Re-run tests before pushing to protected branch." >&2
            rm -f "$STATE_FILE"
            exit 2
        fi
    fi
fi

exit 0
