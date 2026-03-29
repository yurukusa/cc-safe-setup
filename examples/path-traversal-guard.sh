#!/bin/bash
# path-traversal-guard.sh — Block path traversal in Edit/Write operations
#
# Solves: Claude writing files using ../../../ to escape the project
# directory via Edit/Write tools (not caught by scope-guard which
# only watches Bash commands).
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Edit|Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/path-traversal-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]] && exit 0
[[ -z "$FILE" ]] && exit 0

# Block path traversal patterns
if echo "$FILE" | grep -qE '\.\./\.\./|/\.\.\./'; then
    echo "BLOCKED: Path traversal detected: $FILE" >&2
    exit 2
fi

# Block writing to system directories
if echo "$FILE" | grep -qE '^/(etc|usr|bin|sbin|var|boot|proc|sys)/'; then
    echo "BLOCKED: Cannot write to system directory: $FILE" >&2
    exit 2
fi

# Block writing to other users' home directories
if echo "$FILE" | grep -qE '^/home/[^/]+/' && ! echo "$FILE" | grep -qE "^$HOME/"; then
    echo "BLOCKED: Cannot write to another user's directory: $FILE" >&2
    exit 2
fi

exit 0
