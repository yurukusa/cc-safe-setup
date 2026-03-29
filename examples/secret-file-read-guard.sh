#!/bin/bash
# secret-file-read-guard.sh — Block Read/Grep of files containing secrets
#
# Solves: Sensitive data (API keys, credentials, PII) is sent to the
#         LLM provider when Read/Grep tools access configuration files
#         (#39882). This hook blocks reads of known-sensitive files.
#
# How it works: PreToolUse hook that checks if Read/Grep targets a
#   file that commonly contains secrets (.env, credentials, keys, etc.)
#   and blocks the operation before file contents enter the context.
#
# TRIGGER: PreToolUse
# MATCHER: "Read|Grep"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Read|Grep",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/secret-file-read-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

[[ "$TOOL" != "Read" && "$TOOL" != "Grep" ]] && exit 0
[ -z "$FILE" ] && exit 0

# Expand ~ to $HOME
FILE=$(echo "$FILE" | sed "s|^~|$HOME|")

# ============================================
# BLOCKED FILE PATTERNS — customize as needed
# ============================================
BLOCKED_PATTERNS=(
    '\.env$'
    '\.env\.'
    'credentials'
    '\.pem$'
    '\.key$'
    '\.p12$'
    '\.jks$'
    '\.keystore$'
    'id_rsa'
    'id_ed25519'
    '\.ssh/config$'
    '\.aws/credentials$'
    '\.aws/config$'
    '\.npmrc$'
    '\.pypirc$'
    '\.docker/config\.json$'
    '\.kube/config$'
    'secrets\.ya?ml$'
    'vault\.ya?ml$'
    '\.htpasswd$'
    'shadow$'
    'master\.key$'
    'service[-_]account.*\.json$'
)

BASENAME=$(basename "$FILE")
for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$FILE" | grep -qE "$pattern" || echo "$BASENAME" | grep -qE "$pattern"; then
        echo "BLOCKED: Cannot read file that may contain secrets: $FILE" >&2
        echo "This file matches pattern: $pattern" >&2
        echo "If you need this file's contents, describe what you need and the user can provide it." >&2
        exit 2
    fi
done

exit 0
