#!/bin/bash
# ================================================================
# output-credential-scan.sh — Detect credentials in command output
# ================================================================
# PURPOSE:
#   Claude Code can accidentally expose credentials by running
#   commands like `env`, `cat .env`, or `printenv`. This PostToolUse
#   hook scans stdout for common credential patterns and warns.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"
# ================================================================

INPUT=$(cat)
STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty' 2>/dev/null)

[ -z "$STDOUT" ] && exit 0

# Check for common credential patterns in output
if echo "$STDOUT" | grep -qiE '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[A-Z0-9]{16}|xox[bpsa]-[a-zA-Z0-9-]+|eyJ[a-zA-Z0-9_-]+\.eyJ)'; then
    echo "⚠ Possible credential detected in command output!" >&2
    echo "  This output may contain API keys, tokens, or secrets." >&2
    echo "  Avoid sharing this output or committing it to version control." >&2
fi

exit 0
