#!/bin/bash
# bash-trace-guard.sh — Block debug tracing that exposes secrets
#
# Solves: Claude running bash -x which traces all commands including
# expanded secrets from .env files, and SQL queries for credential columns.
# See: https://github.com/anthropics/claude-code/issues/37599
#
# TRIGGER: PreToolUse
# MATCHER: Bash
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/bash-trace-guard.sh"
#       }]
#     }]
#   }
# }

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-bash-trace-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [bash-trace-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Block bash debug tracing (expands all variables including secrets)
if echo "$COMMAND" | grep -qE 'bash\s+(-[a-z]*x|-x)|set\s+-x|set\s+-o\s+xtrace|bash\s+--debug'; then
    echo "BLOCKED: Debug tracing exposes expanded variables including secrets" >&2
    echo "Use 'echo' statements for debugging instead of bash -x." >&2
    exit 2
fi

# Block source .env followed by echo/printenv (secret exfiltration)
if echo "$COMMAND" | grep -qE '(source|\.)\s+\.env.*&&.*(echo|printenv|env|set\b)'; then
    echo "BLOCKED: Sourcing .env and printing environment exposes secrets" >&2
    exit 2
fi

# Block SQL queries targeting credential columns
if echo "$COMMAND" | grep -qiE 'SELECT.*\b(password|secret|token|api_key|private_key|access_key)\b.*FROM'; then
    echo "BLOCKED: SQL query targets credential columns" >&2
    echo "Query non-sensitive columns, or use application-level access." >&2
    exit 2
fi

exit 0
