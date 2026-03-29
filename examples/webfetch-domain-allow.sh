#!/bin/bash
# ================================================================
# webfetch-domain-allow.sh — Auto-approve WebFetch for allowed domains
# ================================================================
# PURPOSE:
#   WebFetch(domain:*) in settings.json silently fails to match in
#   many configurations (especially sandbox mode). This hook reads
#   the requested URL, extracts the domain, and auto-approves if
#   it matches a configurable allowlist.
#
# TRIGGER: PreToolUse
# MATCHER: "WebFetch"
#
# DECISION: exit 0 with permissionDecision "allow" = auto-approve
#           exit 0 with empty JSON = passthrough (ask user)
#
# CONFIG: Set CC_WEBFETCH_ALLOW_DOMAINS env var (comma-separated)
#   or edit the ALLOWED_DOMAINS array below.
#   Use "*" to allow all domains.
#
# See: https://github.com/anthropics/claude-code/issues/9329
# ================================================================

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only handle WebFetch
[[ "$TOOL" != "WebFetch" ]] && exit 0

# Extract URL from tool input
URL=$(echo "$INPUT" | jq -r '.tool_input.url // empty' 2>/dev/null)
[ -z "$URL" ] && exit 0

# Extract domain from URL
DOMAIN=$(echo "$URL" | sed -E 's|^https?://||' | sed 's|/.*||' | sed 's|:.*||')
[ -z "$DOMAIN" ] && exit 0

# ========================================
# DOMAIN ALLOWLIST — edit to your needs
# ========================================
# Option 1: Environment variable (comma-separated)
#   export CC_WEBFETCH_ALLOW_DOMAINS="docs.anthropic.com,github.com,*.example.com"
# Option 2: Edit this array directly
ALLOWED_DOMAINS=(
    "*"  # Allow all domains — change to specific domains for tighter control
    # "docs.anthropic.com"
    # "github.com"
    # "*.github.io"
    # "developer.mozilla.org"
)

# Override from env if set
if [ -n "$CC_WEBFETCH_ALLOW_DOMAINS" ]; then
    IFS=',' read -ra ALLOWED_DOMAINS <<< "$CC_WEBFETCH_ALLOW_DOMAINS"
fi

# Check domain against allowlist
for pattern in "${ALLOWED_DOMAINS[@]}"; do
    pattern=$(echo "$pattern" | xargs)  # trim whitespace
    # Wildcard: allow everything
    if [ "$pattern" = "*" ]; then
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow"
          }
        }'
        exit 0
    fi
    # Glob pattern: *.example.com matches sub.example.com
    if [[ "$pattern" == \** ]]; then
        suffix="${pattern#\*}"
        if [[ "$DOMAIN" == *"$suffix" ]]; then
            jq -n '{
              hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "allow"
              }
            }'
            exit 0
        fi
    fi
    # Exact match
    if [ "$DOMAIN" = "$pattern" ]; then
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow"
          }
        }'
        exit 0
    fi
done

# Not in allowlist — passthrough to normal permission flow
exit 0
