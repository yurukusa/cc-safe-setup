#!/bin/bash
# no-deploy-friday.sh — Block deploys on Fridays
# TRIGGER: PreToolUse  MATCHER: "Bash"
# "Don't deploy on Friday" — every ops team ever
COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0
DOW=$(date +%u)  # 5 = Friday
if [ "$DOW" = "5" ]; then
    if echo "$COMMAND" | grep -qiE '(deploy|firebase|vercel|netlify|fly\s+deploy|heroku|aws\s+s3\s+sync|kubectl\s+apply|docker\s+push)'; then
        echo "BLOCKED: No deploys on Friday." >&2
        echo "Come back Monday." >&2
        exit 2
    fi
fi
exit 0
