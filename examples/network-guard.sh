#!/bin/bash
# network-guard.sh — Warn on network commands that send file contents
#
# Solves: Prompt injection causing data exfiltration via curl/wget (#37420)
# This is a warning hook (exit 0), not a blocker (exit 2),
# because legitimate commands like gh pr create also match.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/network-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Skip safe network commands
if echo "$COMMAND" | grep -qE '^\s*(gh\s|git\s|npm\s|pip\s|curl\s+-s\s+https://api\.|wget\s+-q)'; then
    exit 0
fi

# Warn on commands that POST file contents to external URLs
if echo "$COMMAND" | grep -qE 'curl\s.*(-d\s+@|-F\s+file=|--data-binary\s+@|--upload-file)'; then
    echo "" >&2
    echo "⚠ SECURITY: curl sending file contents to external URL" >&2
    echo "Command: $COMMAND" >&2
    echo "$(date -Iseconds) NETWORK-WARN: $COMMAND" >> "${HOME}/.claude/security-audit.log" 2>/dev/null
fi

# Warn on wget/curl POST to non-standard domains
if echo "$COMMAND" | grep -qE 'curl\s.*-X\s*POST' && ! echo "$COMMAND" | grep -qE '(github\.com|api\.anthropic|localhost|127\.0\.0\.1)'; then
    echo "" >&2
    echo "⚠ SECURITY: POST request to external domain" >&2
    echo "Command: $COMMAND" >&2
    echo "$(date -Iseconds) NETWORK-WARN: $COMMAND" >> "${HOME}/.claude/security-audit.log" 2>/dev/null
fi

# Warn on piping sensitive files to network commands
if echo "$COMMAND" | grep -qE '(cat|base64)\s+.*(\.env|credentials|\.pem|\.key|id_rsa).*\|.*(curl|wget|nc|ncat)'; then
    echo "" >&2
    echo "⚠ SECURITY: Sensitive file piped to network command" >&2
    echo "Command: $COMMAND" >&2
    echo "$(date -Iseconds) NETWORK-WARN: $COMMAND" >> "${HOME}/.claude/security-audit.log" 2>/dev/null
fi

exit 0
