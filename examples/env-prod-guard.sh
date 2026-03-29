#!/bin/bash
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
if echo "$COMMAND" | grep -qiE "(NODE_ENV|RAILS_ENV|FLASK_ENV)=production"; then echo "WARNING: Production env detected in command" >&2; fi
exit 0
