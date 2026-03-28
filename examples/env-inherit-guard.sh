#!/bin/bash
# ================================================================
# env-inherit-guard.sh — Detect inherited production env vars in
# Claude Code's bash environment
#
# Solves: Claude Code inherits the user's shell environment, which
# may contain production database URLs, API keys, or other
# credentials from sourced .env files. This causes accidental
# production data access. (#401, 54 reactions)
#
# Unlike env-source-guard (which blocks explicit sourcing),
# this hook detects when dangerous env vars are ALREADY present
# in the inherited environment before any command runs.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/env-inherit-guard.sh" }]
#     }]
#   }
# }
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Only check on commands that could be affected by env vars
# Skip simple read-only commands
case "$COMMAND" in
    ls*|pwd|echo*|cat*|head*|tail*|wc*|grep*|find*|which*) exit 0 ;;
esac

# Check for dangerous inherited env vars
WARNINGS=""

# Database URLs
for VAR in DATABASE_URL DB_HOST DB_CONNECTION MONGODB_URI REDIS_URL MYSQL_HOST PGHOST; do
    VAL=$(printenv "$VAR" 2>/dev/null)
    if [[ -n "$VAL" ]]; then
        # Check if it looks like production
        if echo "$VAL" | grep -qiE '(prod|production|live|master\.|main\.|primary)'; then
            WARNINGS="${WARNINGS}  ⚠ $VAR contains production-like value\n"
        fi
    fi
done

# API keys that shouldn't be in Claude's environment
for VAR in AWS_SECRET_ACCESS_KEY STRIPE_SECRET_KEY SENDGRID_API_KEY TWILIO_AUTH_TOKEN; do
    if [[ -n "$(printenv "$VAR" 2>/dev/null)" ]]; then
        WARNINGS="${WARNINGS}  ⚠ $VAR is set in environment (credential leak risk)\n"
    fi
done

if [[ -n "$WARNINGS" ]]; then
    echo "WARNING: Inherited environment contains sensitive variables:" >&2
    echo -e "$WARNINGS" >&2
    echo "These may have been loaded from .env files before Claude started." >&2
    echo "Consider: unset these vars, or use env -i for sensitive commands." >&2
fi

exit 0
