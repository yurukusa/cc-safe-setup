#!/bin/bash
# ================================================================
# ssh-key-protect.sh — Block reading/copying SSH private keys
# ================================================================
# PURPOSE:
#   Prevents Claude from reading SSH private keys (id_rsa, id_ed25519)
#   or copying them elsewhere. A prompt injection in a cloned repo
#   could instruct Claude to exfiltrate keys.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Detect reading SSH keys
if echo "$COMMAND" | grep -qE '\b(cat|head|tail|less|more|base64|xxd)\s+.*\.(ssh|gnupg)/(id_|.*_key)'; then
    echo "BLOCKED: Reading SSH/GPG private key" >&2
    exit 2
fi

# Detect copying SSH keys
if echo "$COMMAND" | grep -qE '\b(cp|mv|scp|rsync)\s+.*\.ssh/(id_|.*_key)'; then
    echo "BLOCKED: Copying SSH private key" >&2
    exit 2
fi

# Detect encoding keys for exfiltration
if echo "$COMMAND" | grep -qE 'base64.*\.ssh|\.ssh.*base64|cat.*id_rsa|cat.*id_ed25519'; then
    echo "BLOCKED: Potential SSH key exfiltration" >&2
    exit 2
fi

exit 0
