#!/bin/bash
# pii-upload-guard.sh — Detect PII in outbound data before upload
#
# Solves: Claude uploaded physical coordinates to a public website
# despite CLAUDE.md stating "no PII" for 17 sessions. CLAUDE.md
# instructions are suggestions; hooks are enforcement. (#46910)
#
# How it works: Scans Bash commands for outbound data operations
# (curl POST/PUT, scp, rsync to remote, git push with config files)
# and checks if the data being sent contains PII patterns:
# coordinates, emails, phone numbers, API keys, addresses.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only check outbound data commands
IS_OUTBOUND=0
if echo "$CMD" | grep -qiE 'curl\s+.*-X\s*(POST|PUT|PATCH)|curl\s+.*--data|curl\s+.*-d\s'; then
    IS_OUTBOUND=1
elif echo "$CMD" | grep -qiE '\bscp\b.*:|\brsync\b.*:|\bsftp\b'; then
    IS_OUTBOUND=1
elif echo "$CMD" | grep -qiE 'curl\s+.*upload|wget\s+.*--post'; then
    IS_OUTBOUND=1
fi

[ "$IS_OUTBOUND" -eq 0 ] && exit 0

# Check for PII patterns in the command
PII_FOUND=""

# GPS coordinates (latitude/longitude pairs)
if echo "$CMD" | grep -qE '[-]?[0-9]{1,3}\.[0-9]{4,}.*[-]?[0-9]{1,3}\.[0-9]{4,}'; then
    PII_FOUND="GPS coordinates"
fi

# Email addresses
if echo "$CMD" | grep -qiE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'; then
    PII_FOUND="${PII_FOUND:+$PII_FOUND, }email address"
fi

# Phone numbers (various formats)
if echo "$CMD" | grep -qE '\+?[0-9]{1,4}[-. ]?\(?[0-9]{1,4}\)?[-. ]?[0-9]{3,4}[-. ]?[0-9]{3,4}'; then
    PII_FOUND="${PII_FOUND:+$PII_FOUND, }phone number"
fi

# API keys / tokens (long hex or base64 strings in data)
if echo "$CMD" | grep -qE '(key|token|secret|password|api_key|apikey)=[A-Za-z0-9+/=_-]{20,}'; then
    PII_FOUND="${PII_FOUND:+$PII_FOUND, }API key/token"
fi

# Physical addresses (street patterns)
if echo "$CMD" | grep -qiE '[0-9]+\s+(street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln)\b'; then
    PII_FOUND="${PII_FOUND:+$PII_FOUND, }physical address"
fi

if [ -n "$PII_FOUND" ]; then
    echo "WARNING: Possible PII detected in outbound data: $PII_FOUND" >&2
    echo "  Command: $(echo "$CMD" | head -c 200)" >&2
    echo "  Review the data being sent before proceeding." >&2
    echo "  If this is intentional, acknowledge the PII and re-run." >&2
    # exit 1 = warning (allow with notice), not exit 2 (block)
    # Some legitimate uses send coordinates/emails
    exit 1
fi

exit 0
