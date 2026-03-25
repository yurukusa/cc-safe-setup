#!/bin/bash
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qE 'curl\s+.*(-X\s+POST|-d\s+@|--data-binary|--upload-file)'; then
    echo "WARNING: curl upload/POST detected. Verify no sensitive data." >&2
fi
exit 0
