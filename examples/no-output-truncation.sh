#!/bin/bash
# no-output-truncation.sh — Block piped tail/head that discards command output
#
# Solves: Claude pipes long-running command output through tail/head,
#         discarding errors and falsely reporting success (#39945).
#         Example: `npm test 2>&1 | tail -3` hides crash messages.
#
# How it works: PreToolUse hook on Bash that detects commands piped
#   through tail/head and warns or blocks. Suggests redirecting to a
#   file instead: `cmd > /tmp/output.log 2>&1 && tail -20 /tmp/output.log`
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/no-output-truncation.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect destructive output truncation patterns:
# command | tail -N (discards beginning)
# command | head -N (discards end)
# command 2>&1 | tail (discards stderr too)
if echo "$CMD" | grep -qE '\|\s*(tail|head)\s+-[0-9]'; then
    # Check if it's a build/test/install command being truncated
    DANGEROUS_CMDS="npm test|npm run|yarn test|pnpm test|pytest|cargo test|go test|make|mvn|gradle|node .*\\.js|python .*\\.py|bash .*\\.sh"
    if echo "$CMD" | grep -qE "($DANGEROUS_CMDS).*\|\s*(tail|head)"; then
        echo "BLOCKED: Do not pipe build/test output through tail/head — this discards errors." >&2
        echo "Instead, redirect to a file:" >&2
        echo "  cmd > /tmp/output.log 2>&1; echo \"Exit: \$?\"; tail -30 /tmp/output.log" >&2
        exit 2
    fi
fi

exit 0
