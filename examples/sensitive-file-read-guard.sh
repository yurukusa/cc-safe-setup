#!/bin/bash
# sensitive-file-read-guard.sh — Block reading sensitive system/user files
#
# Solves: Claude Code reading private keys, credentials, password files
#         via the Read tool. Even reading these files exposes secrets in
#         the conversation context, which persists in transcripts.
#
# Detects (via Read tool):
#   ~/.ssh/id_rsa, id_ed25519 (private keys)
#   ~/.gnupg/                 (GPG keys)
#   ~/.aws/credentials        (AWS credentials)
#   /etc/shadow               (password hashes)
#   *.pem, *.key              (certificate private keys)
#   .env.production           (production secrets)
#
# Does NOT block:
#   ~/.ssh/config             (SSH config, no secrets)
#   ~/.ssh/id_rsa.pub         (public keys are fine)
#   /etc/passwd               (no secrets, world-readable)
#   Regular project files
#
# TRIGGER: PreToolUse  MATCHER: "Read"

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

# Block private key files
if echo "$FILE" | grep -qiE '(id_rsa|id_ed25519|id_ecdsa|id_dsa)$'; then
    # Allow .pub files
    echo "$FILE" | grep -qiE '\.pub$' && exit 0
    echo "BLOCKED: Reading private key file: $FILE" >&2
    echo "  Private keys should never be read into conversation context." >&2
    exit 2
fi

# Block certificate private keys
if echo "$FILE" | grep -qiE '\.(pem|key)$' && echo "$FILE" | grep -qiE '(private|server|ssl|tls)'; then
    echo "BLOCKED: Reading certificate private key: $FILE" >&2
    exit 2
fi

# Block credential files
if echo "$FILE" | grep -qiE '\.aws/credentials|\.gcloud/credentials|\.azure/|/etc/shadow|\.gnupg/'; then
    echo "BLOCKED: Reading credential/secret file: $FILE" >&2
    exit 2
fi

# Block production env files
if echo "$FILE" | grep -qiE '\.env\.(production|prod|staging)$'; then
    echo "BLOCKED: Reading production environment file: $FILE" >&2
    echo "  Production secrets should not be in conversation context." >&2
    exit 2
fi

exit 0
