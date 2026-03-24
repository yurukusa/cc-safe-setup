#!/bin/bash
# ================================================================
# stale-env-guard.sh — Warn when .env files are very old
# ================================================================
# PURPOSE:
#   .env files with API keys should be rotated periodically.
#   This hook warns when .env hasn't been modified in 90+ days,
#   suggesting credential rotation.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
#
# CONFIG:
#   CC_ENV_MAX_AGE_DAYS=90
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check on deploy-related or env-reading commands
echo "$COMMAND" | grep -qE '(deploy|source\s+\.env|cat\s+\.env|docker.*\.env)' || exit 0

MAX_DAYS="${CC_ENV_MAX_AGE_DAYS:-90}"

for envfile in .env .env.local .env.production; do
    [ -f "$envfile" ] || continue
    AGE_DAYS=$(( ($(date +%s) - $(stat -c %Y "$envfile" 2>/dev/null || echo 0)) / 86400 ))
    if [ "$AGE_DAYS" -gt "$MAX_DAYS" ]; then
        echo "WARNING: $envfile is $AGE_DAYS days old (threshold: $MAX_DAYS)." >&2
        echo "Consider rotating API keys and credentials." >&2
    fi
done

exit 0
