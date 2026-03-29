#!/bin/bash
# ================================================================
# chmod-guard.sh — Block overly permissive chmod commands
#
# Solves: Claude running chmod 777 or chmod a+rwx on project files,
# creating security vulnerabilities. World-writable files are a
# common attack vector and violate least-privilege principles.
#
# Blocks: chmod 777, chmod 666, chmod a+w, chmod o+w
# Allows: chmod +x (make executable), chmod 755, chmod 644
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/chmod-guard.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check actual chmod commands (not inside echo/printf/comments)
ACTUAL_CMD=$(echo "$COMMAND" | sed 's/echo .*//; s/printf .*//; s/#.*//')
if ! echo "$ACTUAL_CMD" | grep -qE '\bchmod\b'; then
    exit 0
fi

# Block world-writable permissions
if echo "$ACTUAL_CMD" | grep -qE 'chmod\s+(777|666|a\+[rwx]*w|o\+[rwx]*w)'; then
    echo "BLOCKED: World-writable permissions detected." >&2
    echo "Command: $COMMAND" >&2
    echo "" >&2
    echo "chmod 777/666 creates security vulnerabilities." >&2
    echo "Use instead: chmod 755 (dirs) or chmod 644 (files)." >&2
    exit 2
fi

exit 0
