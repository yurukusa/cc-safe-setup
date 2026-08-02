#!/bin/bash
# git-config-guard.sh — Block git config --global modifications
#
# Solves: Claude modifying global git config (user.email, user.name)
# without user consent (#37201)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/git-config-guard.sh" }]
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
  _nojq_warned="/tmp/cc-nojq-warned-git-config-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [git-config-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Block git config --global (any subcommand)
if echo "$COMMAND" | grep -qE '\bgit\s+config\s+--global\b'; then
    echo "BLOCKED: git config --global is not allowed" >&2
    echo "Use --local for project-specific config instead" >&2
    exit 2
fi

# Block git config --system
if echo "$COMMAND" | grep -qE '\bgit\s+config\s+--system\b'; then
    echo "BLOCKED: git config --system is not allowed" >&2
    exit 2
fi

exit 0
