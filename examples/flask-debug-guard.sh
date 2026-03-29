#!/bin/bash
# ================================================================
# flask-debug-guard.sh — Warn when Flask runs with debug=True
#
# Solves: Claude starting Flask with debug mode enabled, which
# exposes the Werkzeug debugger. The debugger allows arbitrary
# code execution and should never run in production.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/flask-debug-guard.sh" }]
#     }]
#   }
# }
# ================================================================
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Check for Flask debug mode
if echo "$COMMAND" | grep -qE 'flask\s+run.*--debug|FLASK_DEBUG=1|FLASK_ENV=development'; then
    echo "WARNING: Flask running with debug mode enabled." >&2
    echo "The Werkzeug debugger allows arbitrary code execution." >&2
    echo "Never expose this to a network. Use for local dev only." >&2
fi

exit 0
