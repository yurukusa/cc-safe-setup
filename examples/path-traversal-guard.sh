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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-path-traversal-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [path-traversal-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
