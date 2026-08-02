#!/bin/bash
# api-key-in-url-guard.sh — Block API keys embedded in URLs
#
# Solves: Claude Code embedding API keys directly in curl/wget URLs
#         instead of using headers or environment variables.
#         Keys in URLs appear in shell history, server logs, proxy logs,
#         and error messages — all places where secrets shouldn't be.
#
# Detects:
#   curl https://api.example.com?key=abc123
#   curl https://api.example.com?api_key=abc123
#   curl https://api.example.com?token=abc123
#   wget "https://...?secret=..."
#
# Does NOT block:
#   curl -H "Authorization: Bearer $TOKEN" https://...
#   curl with env vars: $API_KEY in header
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-api-key-in-url-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [api-key-in-url-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Only check commands that make HTTP requests
echo "$COMMAND" | grep -qE '\b(curl|wget|http|fetch)\b' || exit 0

# Check for API key patterns in URLs
if echo "$COMMAND" | grep -qiP '[?&](api[_-]?key|token|secret|password|auth|access[_-]?key|client[_-]?secret)=[^$\s&"'\'']{8,}'; then
    echo "BLOCKED: API key detected in URL query parameter." >&2
    echo "" >&2
    echo "Command: $(echo "$COMMAND" | head -1)" >&2
    echo "" >&2
    echo "API keys in URLs appear in:" >&2
    echo "  - Shell history (~/.bash_history)" >&2
    echo "  - Server access logs" >&2
    echo "  - Proxy/CDN logs" >&2
    echo "" >&2
    echo "Use headers instead:" >&2
    echo "  curl -H 'Authorization: Bearer \$TOKEN' https://..." >&2
    echo "  curl -H 'X-API-Key: \$API_KEY' https://..." >&2
    exit 2
fi

exit 0
