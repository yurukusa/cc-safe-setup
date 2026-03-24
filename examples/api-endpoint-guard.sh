#!/bin/bash
# ================================================================
# api-endpoint-guard.sh — Warn on requests to internal/sensitive APIs
# ================================================================
# PURPOSE:
#   Claude sometimes sends requests to localhost, internal APIs,
#   or metadata endpoints that could leak credentials or cause
#   unintended side effects.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check curl/wget/http commands
echo "$COMMAND" | grep -qE '^\s*(curl|wget|http|fetch)' || exit 0

# Check for internal/sensitive URLs
if echo "$COMMAND" | grep -qiE '(169\.254\.169\.254|metadata\.google|metadata\.aws)'; then
    echo "BLOCKED: Request to cloud metadata endpoint detected." >&2
    echo "This could leak IAM credentials." >&2
    exit 2
fi

if echo "$COMMAND" | grep -qiE 'localhost:[0-9]+/(admin|api/internal|_debug|actuator)'; then
    echo "WARNING: Request to internal API endpoint." >&2
    echo "Verify this is intentional." >&2
fi

exit 0
