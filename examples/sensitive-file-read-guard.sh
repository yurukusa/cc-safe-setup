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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-sensitive-file-read-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [sensitive-file-read-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE" ] && exit 0

# Block private key files.
# The optional suffix group matters: a backup of a private key is exactly as
# sensitive as the key, and id_rsa.bak / id_rsa_old / id_rsa.orig slipped
# through the bare "$" anchor - measured 2026-08-29 on CC 2.1.246.
# ".pub" is deliberately NOT in the suffix list, so public keys still pass.
if echo "$FILE" | grep -qiE '(id_rsa|id_ed25519|id_ecdsa|id_dsa)([._-](bak|old|orig|save|copy|backup|[0-9]+))?$'; then
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
