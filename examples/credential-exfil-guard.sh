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
#   env | grep JIRA        (warns — an env dump piped to grep prints values even when the term is not a secret keyword, #69053)
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

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-credential-exfil-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [credential-exfil-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Pattern 1: env/printenv piped to grep for secrets
if echo "$COMMAND" | grep -qiE '(env|printenv|set)\s*\|.*grep.*\b(token|secret|key|password|credential|auth|oauth|cookie|session|api.key)\b'; then
    echo "BLOCKED: Credential hunting via environment variable scanning" >&2
    exit 2
fi

# Pattern 1b: env/printenv piped to grep by a NON-secret term still dumps the
# matching live VALUES. In #69053, `env | grep JIRA` dumped JIRA_API_TOKEN — the
# filter term ("JIRA") is not a secret keyword so Pattern 1 misses it, and it is
# not a bare dump so Pattern 7 misses it, so it passed silently. Warn (not block)
# to stay consistent with Pattern 7 and avoid over-blocking benign `env | grep PATH`.
if echo "$COMMAND" | grep -qiE '(env|printenv|set)\s*\|.*grep'; then
    echo "WARNING: piping an environment dump to grep prints the matching live values into the transcript/API; if a matched variable holds a token it is now exposed (#69053). To find where a credential is configured, grep config files for the variable NAME instead of dumping environment values." >&2
    exit 0
fi

# Pattern 2: find searching for credential files
if echo "$COMMAND" | grep -qiE 'find\s.*-name\s.*\*?(token|secret|credential|password|\.key|\.pem|\.p12|\.pfx|\.keystore|\.jks|\.env)'; then
    echo "BLOCKED: Credential hunting via file system search" >&2
    exit 2
fi

# Pattern 3: Direct access to known credential locations
# 2026-08-30: the home alternation used to be (~|/home|/root), which only matches
#   when /.ssh follows /home directly. Real paths carry a username segment
#   (/home/alice/.ssh/id_rsa), so the tilde form was blocked while the expanded
#   form walked straight through - measured on this machine, rc=2 vs rc=0 for the
#   same file. Whether an agent writes the tilde or the expanded path is arbitrary,
#   so a guard that only sees one of them is a coin flip.
if echo "$COMMAND" | grep -qE 'cat\s+(~|/home/[^/[:space:]]+|/Users/[^/[:space:]]+|/root|/home|/Users)/\.ssh/(id_|authorized_keys|known_hosts|config)'; then
    echo "BLOCKED: Direct SSH credential access" >&2
    exit 2
fi

# Pattern 4: Reading system credential files
if echo "$COMMAND" | grep -qE 'cat\s+(/etc/shadow|/etc/gshadow|/etc/passwd)'; then
    echo "BLOCKED: System credential file access" >&2
    exit 2
fi

# Pattern 5: AWS/cloud credential files
if echo "$COMMAND" | grep -qE 'cat\s+(~|/home/[^/[:space:]]+|/Users/[^/[:space:]]+|/root|/home|/Users)/\.(aws|gcloud|azure|kube)/(credentials|config|token)'; then
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
# Uses -E, not -P: BSD grep (macOS) rejects -P outright, which made this block
# exit 0 and let the upload through. \s/\S are Perl-only, so they are written as
# POSIX classes here.
if echo "$COMMAND" | grep -qiE 'curl[[:space:]].*-d[[:space:]]+@[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)|wget[[:space:]].*--post-file[= ][^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)'; then
    echo "BLOCKED: Credential file exfiltration via HTTP upload" >&2
    exit 2
fi

# Pattern 9: Piping credential files to curl/wget
if echo "$COMMAND" | grep -qiE 'cat[[:space:]]+[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)[^[:space:]]*[[:space:]]*\|.*curl|cat[[:space:]]+[^[:space:]]*(\.env|\.pem|\.key|credentials|\.ssh/id_)[^[:space:]]*[[:space:]]*\|.*wget'; then
    echo "BLOCKED: Credential file piped to HTTP client" >&2
    exit 2
fi

# Pattern 10: macOS keychain extraction of a known secret token (#65350 —
# a plugin shipped `security find-generic-password -s ANTHROPIC_AUTH_TOKEN -w`
# in skill files to silently exfiltrate the user's Anthropic token). Require
# the -w flag (prints the raw secret) AND a high-signal secret service name,
# so reading a non-secret keychain item (e.g. a wifi password) is not blocked.
if echo "$COMMAND" | grep -qiE 'security\s+find-(generic|internet)-password' \
   && echo "$COMMAND" | grep -qE '(^|[[:space:]])-w([[:space:]]|$)' \
   && echo "$COMMAND" | grep -qiE 'ANTHROPIC|OPENAI|AUTH[_-]?TOKEN|API[_-]?KEY|ACCESS[_-]?TOKEN|[_-]SECRET|OAUTH|GITHUB[_-]?TOKEN|(^|[^a-z])secret([^a-z]|$)'; then
    echo "BLOCKED: macOS keychain extraction of a secret token (security find-generic-password -w of a credential)" >&2
    exit 2
fi

# Pattern 11: keychain secret piped straight into a network client.
if echo "$COMMAND" | grep -qiE 'security\s+find-(generic|internet)-password' \
   && echo "$COMMAND" | grep -qiE '\|[[:space:]]*(curl|wget|nc|ncat|telnet)([[:space:]]|$)'; then
    echo "BLOCKED: keychain secret piped to a network client (possible exfiltration)" >&2
    exit 2
fi

# Pattern 12: a secret-named env var piped into a network client as data.
# Legit auth uses a header (-H "Authorization: Bearer $TOKEN") where the pipe,
# if any, goes to a parser like jq — not to the network client — so this only
# fires when the secret value itself is piped straight to curl/wget/nc.
if echo "$COMMAND" | grep -qE '\$\{?[A-Za-z_]*(TOKEN|SECRET|API[_-]?KEY|PASSWORD|CREDENTIAL|AUTH)[A-Za-z_]*' \
   && echo "$COMMAND" | grep -qiE '\|[[:space:]]*(curl|wget|nc|ncat|telnet)([[:space:]]|$)'; then
    echo "BLOCKED: secret environment variable piped to a network client (possible exfiltration)" >&2
    exit 2
fi

exit 0
