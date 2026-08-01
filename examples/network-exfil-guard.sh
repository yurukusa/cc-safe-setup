#!/bin/bash
# network-exfil-guard.sh — Block data exfiltration via network commands
#
# Solves: Claude using curl/wget/nc to send local data to external servers.
#         OWASP MCP Top 10: MCP01 (Secret Exposure via network).
#
# How it works: PreToolUse hook on Bash that detects outbound data transfer
#   commands (POST/PUT with file data, netcat connections, base64-encoded
#   data in URLs) and blocks them.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-network-exfil-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [network-exfil-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Patterns for outbound data exfiltration
BLOCKED=false
REASON=""

# curl/wget sending file contents
if echo "$COMMAND" | grep -qE 'curl\s+.*(-d\s+@|-F\s+.*=@|--data-binary\s+@|--upload-file)'; then
    BLOCKED=true
    REASON="curl uploading local file"
fi

# wget POST with file
if echo "$COMMAND" | grep -qE 'wget\s+.*--post-file'; then
    BLOCKED=true
    REASON="wget posting local file"
fi

# netcat sending data
if echo "$COMMAND" | grep -qE '(nc|ncat|netcat)\s+.*<\s|>\s*(nc|ncat|netcat)'; then
    BLOCKED=true
    REASON="netcat data transfer"
fi

# Pipe sensitive files to network commands
if echo "$COMMAND" | grep -qE 'cat\s+(~/\.|/etc/|/home/).*\|\s*(curl|wget|nc)'; then
    BLOCKED=true
    REASON="piping sensitive file to network command"
fi

# Base64-encoded data in URL (common exfil technique)
if echo "$COMMAND" | grep -qE 'base64.*\|\s*curl|curl.*\$\(.*base64'; then
    BLOCKED=true
    REASON="base64-encoded data in network request"
fi

if $BLOCKED; then
    echo "BLOCKED: Potential data exfiltration detected." >&2
    echo "  Reason: $REASON" >&2
    echo "  Command: $COMMAND" >&2
    exit 2
fi

exit 0
