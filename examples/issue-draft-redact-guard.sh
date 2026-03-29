#!/bin/bash
# issue-draft-redact-guard.sh — Redact sensitive info from public issue drafts
#
# Solves: Claude drafting public bug reports with sensitive project info (#29121).
#         Internal org names, private URLs, IP addresses, and file paths
#         get included in gh issue create commands.
#
# How it works: PreToolUse hook on Bash that intercepts gh issue/pr create
#   commands and scans the body for sensitive patterns.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check issue/PR creation commands
if ! echo "$COMMAND" | grep -qE 'gh\s+(issue|pr)\s+create'; then
  exit 0
fi

# Scan for sensitive patterns in the command body
SENSITIVE_PATTERNS=(
  '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'  # IP addresses
  '(internal|private|corp|staging)\.[a-z]+\.[a-z]+'    # Internal domains
  '/home/[a-zA-Z]+/'                                    # Home directory paths
  '/Users/[a-zA-Z]+/'                                   # macOS home paths
  'password|passwd|secret_key|private_key'               # Secret keywords
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qEi "$pattern"; then
    MATCH=$(echo "$COMMAND" | grep -oEi "$pattern" | head -1)
    echo "WARNING: Sensitive pattern detected in issue draft." >&2
    echo "Pattern match: $MATCH" >&2
    echo "Review and redact before posting publicly." >&2
    # Warn but don't block — user may intentionally include their own info
    break
  fi
done

exit 0
