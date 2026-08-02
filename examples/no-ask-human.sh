#!/bin/bash
# ================================================================
# no-ask-human.sh — Block commands that require human input
# ================================================================
# PURPOSE:
#   During autonomous operation, Claude Code should never run
#   commands that wait for human input (read, select, interactive
#   git rebase, etc.). These cause the session to hang indefinitely.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/no-ask-human.sh"
#       }]
#     }]
#   }
# }
# ================================================================

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-ask-human-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-ask-human]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Interactive input commands
if echo "$COMMAND" | grep -qE '\bread\s+-p\b|\bselect\s|\bexpect\s|\bdialog\s'; then
    echo "BLOCKED: Command requires human input (read -p, select, etc.)" >&2
    echo "Autonomous mode: rewrite to use non-interactive alternatives." >&2
    exit 2
fi

# Interactive git commands
if echo "$COMMAND" | grep -qE 'git\s+rebase\s+-i\b|git\s+add\s+-i\b|git\s+add\s+--interactive'; then
    echo "BLOCKED: Interactive git command not supported in autonomous mode." >&2
    echo "Use non-interactive alternatives (git rebase --onto, git add <files>)." >&2
    exit 2
fi

# Interactive editors
if echo "$COMMAND" | grep -qE '^\s*(vi|vim|nano|emacs|pico)\s'; then
    echo "BLOCKED: Interactive editor not supported in autonomous mode." >&2
    echo "Use Edit tool or sed/awk instead." >&2
    exit 2
fi

exit 0
