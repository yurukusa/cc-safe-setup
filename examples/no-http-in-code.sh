#!/bin/bash
# no-http-in-code.sh — Warn about http:// URLs in code (should be https://)
#
# Prevents: Insecure HTTP connections in production code.
#           localhost URLs are exempt.
#
# TRIGGER: PreToolUse
# MATCHER: "Write|Edit"

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

# Find http:// URLs excluding localhost/127.0.0.1
if echo "$CONTENT" | grep -qE 'http://[^l1\s]' | grep -vE 'http://(localhost|127\.0\.0\.1|0\.0\.0\.0)'; then
  echo "WARNING: http:// URL detected. Use https:// for security." >&2
fi

exit 0
