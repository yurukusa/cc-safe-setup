#!/bin/bash
# ================================================================
# chown-guard.sh — Block dangerous ownership changes
#
# Solves: Claude running chown root or recursive chown on system
# directories, which can break file permissions and lock the user
# out of their own files.
#
# Blocks: chown root, chown -R on system paths, chown on /etc /var
# Allows: chown on project files
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/chown-guard.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-chown-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [chown-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check actual chown commands (not inside echo/printf/comments)
ACTUAL_CMD=$(echo "$COMMAND" | sed 's/echo .*//; s/printf .*//; s/#.*//')
if ! echo "$ACTUAL_CMD" | grep -qE '\bchown\b'; then
    exit 0
fi

# Block chown to root
if echo "$ACTUAL_CMD" | grep -qE 'chown\s+(-R\s+)?root[: ]'; then
    echo "BLOCKED: Changing ownership to root." >&2
    echo "Command: $COMMAND" >&2
    echo "This can lock you out of your files." >&2
    exit 2
fi

# Block recursive chown on system directories
if echo "$ACTUAL_CMD" | grep -qE 'chown\s+-R.*\s+/(etc|var|usr|bin|sbin|lib|boot|sys|proc|dev)\b'; then
    echo "BLOCKED: Recursive chown on system directory." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Block chown on home directory root
if echo "$ACTUAL_CMD" | grep -qE 'chown\s+-R.*\s+(~|/home/\w+)\s*$'; then
    echo "BLOCKED: Recursive chown on entire home directory." >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

exit 0
