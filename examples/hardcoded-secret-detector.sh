#!/bin/bash
# ================================================================
# hardcoded-secret-detector.sh — Detect hardcoded secrets in edits
# ================================================================
# PURPOSE:
#   Claude sometimes hardcodes API keys, passwords, or tokens
#   directly into source files instead of using environment
#   variables. This hook checks edited content for secret patterns.
#
# TRIGGER: PostToolUse  MATCHER: "Edit|Write"
# ================================================================

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Skip config/env files (secrets are expected there)
case "$FILE" in
    *.env*|*credentials*|*secret*|*.key|*.pem) exit 0 ;;
esac

FOUND=0

# AWS keys (AKIA...)
if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    echo "WARNING: Possible AWS access key in $FILE" >&2
    FOUND=1
fi

# Generic API key patterns
if echo "$CONTENT" | grep -qE "(api_key|apikey|api-key|secret_key|access_token)\s*[=:]\s*['\"][a-zA-Z0-9]{20,}['\"]"; then
    echo "WARNING: Possible hardcoded API key in $FILE" >&2
    FOUND=1
fi

# Password patterns
if echo "$CONTENT" | grep -qiE "(password|passwd|pwd)\s*[=:]\s*['\"][^'\"]{8,}['\"]"; then
    echo "WARNING: Possible hardcoded password in $FILE" >&2
    FOUND=1
fi

# JWT tokens
if echo "$CONTENT" | grep -qE 'eyJ[a-zA-Z0-9_-]{20,}\.eyJ[a-zA-Z0-9_-]{20,}'; then
    echo "WARNING: Possible JWT token in $FILE" >&2
    FOUND=1
fi

# Private keys
if echo "$CONTENT" | grep -qE 'BEGIN (RSA |EC |DSA )?PRIVATE KEY'; then
    echo "WARNING: Private key detected in $FILE" >&2
    FOUND=1
fi

if [ "$FOUND" -eq 1 ]; then
    echo "Use environment variables instead of hardcoding secrets." >&2
fi

exit 0
