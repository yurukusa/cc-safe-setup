#!/bin/bash
# no-deploy-friday.sh — Block deploys on Fridays
# TRIGGER: PreToolUse  MATCHER: "Bash|PowerShell"
# "Don't deploy on Friday" — every ops team ever
# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-no-deploy-friday-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [no-deploy-friday]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
