#!/bin/bash
# bash-domain-allowlist.sh — Block curl/wget to unauthorized domains
#
# Solves: Sandbox allowedDomains not enforced for plain HTTP requests,
#         allowing data exfiltration via curl/wget (#40213).
#         Also provides defense-in-depth when sandbox is not available.
#
# How it works: PreToolUse hook on Bash that extracts target domains from
#   curl/wget commands and blocks requests to domains not in the allowlist.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/bash-domain-allowlist.sh" }]
#     }]
#   }
# }
#
# Configuration: Set CC_ALLOWED_DOMAINS env var (comma-separated)
#   or edit the ALLOWED_DOMAINS array below.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only check commands that make HTTP requests
echo "$CMD" | grep -qE '\b(curl|wget|http|fetch)\b' || exit 0

# ========================================
# DOMAIN ALLOWLIST — edit to your needs
# ========================================
if [ -n "$CC_ALLOWED_DOMAINS" ]; then
    IFS=',' read -ra ALLOWED_DOMAINS <<< "$CC_ALLOWED_DOMAINS"
else
    ALLOWED_DOMAINS=(
        "github.com"
        "api.github.com"
        "raw.githubusercontent.com"
        "registry.npmjs.org"
        "pypi.org"
        "*.amazonaws.com"
        "localhost"
        "127.0.0.1"
    )
fi

# Extract target domains from URLs in the command
DOMAINS=$(echo "$CMD" | grep -oE 'https?://[^/"'"'"'"'"'"' ]+' | sed -E 's|^https?://||;s|/.*||;s|:.*||' | sort -u)
[ -z "$DOMAINS" ] && exit 0

for domain in $DOMAINS; do
    allowed=false
    for pattern in "${ALLOWED_DOMAINS[@]}"; do
        # Convert glob to regex (*.example.com -> .*\.example\.com)
        regex=$(echo "$pattern" | sed 's/\./\\./g; s/\*/.*/g')
        if echo "$domain" | grep -qE "^${regex}$"; then
            allowed=true
            break
        fi
    done
    if [ "$allowed" = false ]; then
        echo "BLOCKED: HTTP request to unauthorized domain: $domain" >&2
        echo "Allowed: ${ALLOWED_DOMAINS[*]}" >&2
        exit 2
    fi
done
exit 0
