#!/bin/bash
# bash-secret-output-detector.sh — Warn when Bash output contains secrets
#
# Solves: Bash command output containing API keys, tokens, or credentials
#         enters the LLM context window and gets sent to the API provider
#         (#39882). PostToolUse hook that scans stdout for secret patterns.
#
# How it works: PostToolUse hook on Bash that checks command stdout for
#   patterns matching API keys, tokens, passwords, and connection strings.
#   Emits a systemMessage warning the model to ignore/not repeat secrets.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/bash-secret-output-detector.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)

[ -z "$STDOUT" ] && exit 0

# Secret patterns (high-confidence, low false-positive)
FOUND=""

# AWS keys
if echo "$STDOUT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    FOUND="${FOUND}AWS access key, "
fi

# Generic API keys/tokens (long hex/base64 strings after key= or token=)
if echo "$STDOUT" | grep -qiE '(api[_-]?key|api[_-]?secret|auth[_-]?token|access[_-]?token|secret[_-]?key)\s*[:=]\s*\S{20,}'; then
    FOUND="${FOUND}API key/token, "
fi

# Connection strings with passwords
if echo "$STDOUT" | grep -qiE '(mysql|postgres|mongodb|redis)://[^:]+:[^@]+@'; then
    FOUND="${FOUND}database connection string, "
fi

# Private keys
if echo "$STDOUT" | grep -qE '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'; then
    FOUND="${FOUND}private key, "
fi

# JWT tokens
if echo "$STDOUT" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+'; then
    FOUND="${FOUND}JWT token, "
fi

# GitHub/GitLab tokens
if echo "$STDOUT" | grep -qE '(ghp|gho|ghs|ghr|glpat)_[A-Za-z0-9]{30,}'; then
    FOUND="${FOUND}GitHub/GitLab token, "
fi

if [ -n "$FOUND" ]; then
    FOUND="${FOUND%, }"
    echo "{\"systemMessage\":\"⚠ SECRET DETECTED in command output: ${FOUND}. Do NOT repeat, log, or include these values in any output. They are now in context but should be treated as redacted.\"}"
fi

exit 0
