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
