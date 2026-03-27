#!/bin/bash
# no-self-signed-cert.sh — Warn when generating self-signed certificates
#
# Prevents: Self-signed certs being used in production.
#           Claude sometimes generates certs for "testing" that stay.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

if echo "$COMMAND" | grep -qE 'openssl\s+req.*-x509|-newkey.*-nodes.*-keyout|mkcert'; then
  echo "WARNING: Self-signed certificate generation detected." >&2
  echo "  OK for development. Do NOT use in production." >&2
fi

exit 0
