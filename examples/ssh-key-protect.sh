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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-ssh-key-protect-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [ssh-key-protect]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

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
