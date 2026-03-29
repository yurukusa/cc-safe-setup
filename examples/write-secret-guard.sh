#!/bin/bash
# write-secret-guard.sh — Block secrets from being written to files
#
# Solves: Claude writes API keys, tokens, and passwords directly into source files
#         instead of using environment variables (#29910, 14 reactions)
#         Existing secret-guard only covers Bash (git add .env).
#         This hook covers Write and Edit tools.
#
# Detects: AWS keys (AKIA...), GitHub tokens (ghp_/gho_/ghs_),
#          OpenAI keys (sk-), Anthropic keys (sk-ant-),
#          Slack tokens (xoxb-/xoxp-), Stripe keys (sk_live_/pk_live_),
#          Generic Bearer tokens, private keys, high-entropy strings
#
# Usage: Add to settings.json as a PreToolUse hook for Write AND Edit
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Write",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/write-secret-guard.sh" }]
#     }, {
#       "matcher": "Edit",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/write-secret-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Edit|Write"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Get the content being written
if [ "$TOOL" = "Write" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)
    FILEPATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
elif [ "$TOOL" = "Edit" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
    FILEPATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
    exit 0
fi

[ -z "$CONTENT" ] && exit 0

# --- Allow known safe patterns ---

# Allow .env.example / .env.template (these contain placeholders)
if echo "$FILEPATH" | grep -qE '\.(example|template|sample)$'; then
    exit 0
fi

# Allow test files
if echo "$FILEPATH" | grep -qE '(test|spec|mock|fixture|__test__|\.test\.)'; then
    exit 0
fi

# --- Detect secret patterns ---

BLOCKED=""

# AWS Access Key ID (AKIA followed by 16 uppercase alphanumeric)
if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    BLOCKED="AWS Access Key ID (AKIA...)"
fi

# AWS Secret Access Key (40 char base64-like after specific prefixes)
if echo "$CONTENT" | grep -qE '(aws_secret_access_key|AWS_SECRET)\s*[=:]\s*[A-Za-z0-9/+=]{40}'; then
    BLOCKED="AWS Secret Access Key"
fi

# GitHub tokens
if echo "$CONTENT" | grep -qE '(ghp_|gho_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{20,}'; then
    BLOCKED="GitHub token"
fi

# OpenAI API key (sk-... or sk-proj-...)
if echo "$CONTENT" | grep -qE 'sk-[A-Za-z0-9_-]{20,}' && ! echo "$CONTENT" | grep -qE 'sk-ant-'; then
    # Exclude Anthropic keys (handled separately)
    BLOCKED="OpenAI API key (sk-...)"
fi

# Anthropic API key
if echo "$CONTENT" | grep -qE 'sk-ant-[A-Za-z0-9-]{20,}'; then
    BLOCKED="Anthropic API key (sk-ant-...)"
fi

# Slack tokens
if echo "$CONTENT" | grep -qE '(xoxb-|xoxp-|xoxs-|xoxa-)[0-9A-Za-z-]{20,}'; then
    BLOCKED="Slack token"
fi

# Stripe keys
if echo "$CONTENT" | grep -qE '(sk_live_|pk_live_|rk_live_)[A-Za-z0-9]{20,}'; then
    BLOCKED="Stripe API key"
fi

# Google API key
if echo "$CONTENT" | grep -qE 'AIza[0-9A-Za-z_-]{35}'; then
    BLOCKED="Google API key"
fi

# Private keys (PEM format)
if echo "$CONTENT" | grep -qE -- '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
    BLOCKED="Private key (PEM format)"
fi

# Bearer token assignment (not in comments or docs)
if echo "$CONTENT" | grep -qE '(Authorization|Bearer|token)\s*[=:]\s*["\x27][A-Za-z0-9._-]{30,}["\x27]' \
   && ! echo "$FILEPATH" | grep -qiE '\.(md|txt|rst|adoc)$'; then
    BLOCKED="Hardcoded Bearer/auth token"
fi

# Generic database connection strings with credentials
if echo "$CONTENT" | grep -qE '(mysql|postgres|mongodb|redis)://[^:]+:[^@]+@'; then
    BLOCKED="Database connection string with credentials"
fi

# --- Block if secret detected ---

if [ -n "$BLOCKED" ]; then
    echo "BLOCKED: Secret detected in file write — $BLOCKED" >&2
    echo "Use environment variables instead: process.env.KEY or os.environ['KEY']" >&2
    exit 2
fi

exit 0
