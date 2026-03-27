#!/bin/bash
# no-hardcoded-ip.sh — Detect hardcoded IP addresses in code
#
# Prevents: Hardcoded IPs that break in different environments.
#           Use environment variables or DNS names instead.
#
# TRIGGER: PreToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

# Skip if writing to config/env files (IPs are expected there)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$FILE" in
  *.env|*/.env.*|*/hosts|*/docker-compose*|*Vagrantfile*) exit 0 ;;
esac

# Detect IPv4 addresses (excluding 127.0.0.1 and 0.0.0.0)
if echo "$CONTENT" | grep -qE '["\x27]([0-9]{1,3}\.){3}[0-9]{1,3}["\x27]' | grep -vE '127\.0\.0\.1|0\.0\.0\.0|localhost'; then
  echo "WARNING: Hardcoded IP address detected." >&2
  echo "  Use environment variables or DNS names for portability." >&2
fi

exit 0
