#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE 'curl\s+.*(-X\s+POST|--data|--upload-file|-F\s).*[^localhost]'; then
    HOST=$(echo "$COMMAND" | grep -oE 'https?://[^/ ]+' | head -1)
    case "$HOST" in *localhost*|*127.0.0.1*|*github.com*|*npmjs.org*) exit 0 ;; esac
    echo "WARNING: Data upload to external host: $HOST" >&2
fi
exit 0
