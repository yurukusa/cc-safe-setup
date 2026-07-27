#!/bin/bash
#
# TRIGGER: PostToolUse  MATCHER: "Bash"
OUTPUT=$(cat | jq -r '.tool_result // empty' 2>/dev/null)
[ -z "$OUTPUT" ] && exit 0
echo "$OUTPUT" | grep -qiE 'password|api.key|secret.key|bearer\s+[a-zA-Z0-9]' && echo "WARNING: Secret in output" >&2
exit 0
