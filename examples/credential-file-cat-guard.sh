#!/bin/bash
# credential-file-cat-guard.sh — Block cat/read of package manager credential files
#
# Solves: Agent displays full credential files in conversation
#         (#34819 — cat ~/.netrc, ~/.npmrc, ~/.cargo/credentials.toml displayed all tokens)
#
# Complements credential-exfil-guard.sh which blocks hunting patterns.
# This hook blocks direct read of known credential files that the
# exfil guard misses: .netrc, .npmrc, .cargo/credentials, .docker/config.json, etc.
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/credential-file-cat-guard.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0

# Known credential files that contain tokens/passwords
CRED_FILES='\.netrc|\.npmrc|\.yarnrc\.yml|\.cargo/credentials|\.docker/config\.json|\.kube/config|\.config/gh/hosts\.yml|\.nuget/NuGet\.Config|\.m2/settings\.xml|\.gradle/gradle\.properties|\.pypirc|\.gem/credentials|\.config/pip/pip\.conf|\.bowerrc|\.composer/auth\.json'

# Block cat/head/tail/less/more/grep reading credential files
if echo "$COMMAND" | grep -qE "(cat|head|tail|less|more|bat)\s+[^\|;]*($CRED_FILES)"; then
    FILE=$(echo "$COMMAND" | grep -oE "[~\/][^\s;|]*($CRED_FILES)[^\s;|]*" | head -1)
    echo "BLOCKED: Reading credential file: $FILE" >&2
    echo "  These files contain authentication tokens. Use environment variables instead." >&2
    exit 2
fi

# Block grep searching inside credential files
if echo "$COMMAND" | grep -qE "grep\s+.*\s+[^\|;]*($CRED_FILES)"; then
    echo "BLOCKED: Searching inside credential file" >&2
    exit 2
fi

exit 0
