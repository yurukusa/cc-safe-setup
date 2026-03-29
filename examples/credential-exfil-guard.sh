#!/bin/bash
# credential-exfil-guard.sh — Block credential hunting commands
#
# Solves: Agents scanning for tokens, secrets, and credentials without permission
#         (#37845 — 48 bash commands auto-executed to exfiltrate credentials)
#
# Detects patterns like:
#   env | grep -i token
#   find / -name "*.token" -o -name "*credentials*"
#   cat ~/.ssh/id_rsa
#   printenv | grep SECRET
#   cat /etc/shadow
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/credential-exfil-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Pattern 1: env/printenv piped to grep for secrets
if echo "$COMMAND" | grep -qiE '(env|printenv|set)\s*\|.*grep.*\b(token|secret|key|password|credential|auth|oauth|cookie|session|api.key)\b'; then
    echo "BLOCKED: Credential hunting via environment variable scanning" >&2
    exit 2
fi

# Pattern 2: find searching for credential files
if echo "$COMMAND" | grep -qiE 'find\s.*-name\s.*\*?(token|secret|credential|password|\.key|\.pem|\.p12|\.pfx|\.keystore|\.jks|\.env)'; then
    echo "BLOCKED: Credential hunting via file system search" >&2
    exit 2
fi

# Pattern 3: Direct access to known credential locations
if echo "$COMMAND" | grep -qE 'cat\s+(~|/home|/root)/.ssh/(id_|authorized_keys|known_hosts|config)'; then
    echo "BLOCKED: Direct SSH credential access" >&2
    exit 2
fi

# Pattern 4: Reading system credential files
if echo "$COMMAND" | grep -qE 'cat\s+(/etc/shadow|/etc/gshadow|/etc/passwd)'; then
    echo "BLOCKED: System credential file access" >&2
    exit 2
fi

# Pattern 5: AWS/cloud credential files
if echo "$COMMAND" | grep -qE 'cat\s+(~|/home|/root)/\.(aws|gcloud|azure|kube)/(credentials|config|token)'; then
    echo "BLOCKED: Cloud provider credential access" >&2
    exit 2
fi

# Pattern 6: Browser credential stores
if echo "$COMMAND" | grep -qiE 'find\s.*\.(chrome|firefox|mozilla|safari).*\b(login|password|cookie|token)\b'; then
    echo "BLOCKED: Browser credential hunting" >&2
    exit 2
fi

# Pattern 7: Dumping all environment variables (without filtering)
if echo "$COMMAND" | grep -qE '^\s*(env|printenv|set)\s*$'; then
    echo "WARNING: Dumping all environment variables may expose secrets" >&2
    # Don't block, just warn — some legitimate uses exist
    exit 0
fi

# Pattern 8: curl/wget posting credential files
if echo "$COMMAND" | grep -qiP 'curl\s.*-d\s+@[^\s]*(\.env|\.pem|\.key|credentials|\.ssh/id_)|wget\s.*--post-file[= ][^\s]*(\.env|\.pem|\.key|credentials|\.ssh/id_)'; then
    echo "BLOCKED: Credential file exfiltration via HTTP upload" >&2
    exit 2
fi

# Pattern 9: Piping credential files to curl/wget
if echo "$COMMAND" | grep -qiP 'cat\s+[^\s]*(\.env|\.pem|\.key|credentials|\.ssh/id_)\S*\s*\|.*curl|cat\s+[^\s]*(\.env|\.pem|\.key|credentials|\.ssh/id_)\S*\s*\|.*wget'; then
    echo "BLOCKED: Credential file piped to HTTP client" >&2
    exit 2
fi

exit 0
