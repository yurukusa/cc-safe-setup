#!/bin/bash
# prefer-dedicated-tools.sh — Force use of dedicated tools instead of Bash equivalents
#
# Solves: Claude uses Bash cat/grep/head/tail instead of dedicated Read/Grep
#         tools, wasting tokens on shell overhead and losing structured output
#         (#39979). The system prompt says to use dedicated tools, but the
#         model ignores it.
#
# How it works: PreToolUse hook on Bash that detects file-reading commands
#   and blocks them with a suggestion to use the dedicated tool instead.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/prefer-dedicated-tools.sh" }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-prefer-dedicated-tools-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [prefer-dedicated-tools]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Detect cat used for reading files (not piped)
if echo "$CMD" | grep -qE '^\s*cat\s+[^|]+$'; then
    echo "BLOCKED: Use the Read tool instead of 'cat' for reading files." >&2
    exit 2
fi

# Detect head/tail used for reading files
if echo "$CMD" | grep -qE '^\s*(head|tail)\s+(-[0-9]+\s+)?[^|]+$'; then
    echo "BLOCKED: Use the Read tool (with offset/limit) instead of head/tail." >&2
    exit 2
fi

# Detect grep used for searching (not piped)
if echo "$CMD" | grep -qE '^\s*grep\s+(-[a-zA-Z]*\s+)*[^|]+$' && ! echo "$CMD" | grep -qE '\|'; then
    echo "BLOCKED: Use the Grep tool instead of 'grep' for searching files." >&2
    exit 2
fi

# Detect find used for file discovery
if echo "$CMD" | grep -qE '^\s*find\s+\S+\s+-name\s'; then
    echo "BLOCKED: Use the Glob tool instead of 'find' for file discovery." >&2
    exit 2
fi

# Allow piped commands (cat file | grep pattern is a valid use case)
# Allow other legitimate bash usage
exit 0
