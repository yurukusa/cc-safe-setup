#!/bin/bash
# no-hardlink.sh — Warn on hard link creation
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE '\bln\b' && ! echo "$COMMAND" | grep -q '\-s'; then
    echo "WARNING: Hard link creation detected. Use symbolic links (ln -s) instead." >&2
fi
exit 0
