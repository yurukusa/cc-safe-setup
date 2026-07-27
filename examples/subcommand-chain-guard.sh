#!/bin/bash
# subcommand-chain-guard.sh — Block commands with excessive subcommand chains
#
# Solves: Claude Code silently ignores deny rules when a command contains
# 50+ subcommands (MAX_SUBCOMMANDS_FOR_SECURITY_CHECK = 50).
# Attackers chain 50 no-op "true" commands before a dangerous command
# to bypass all security checks. (Adversa AI / CVE disclosure, April 2026)
#
# How it works: Counts semicolon-separated and &&/|| chained subcommands.
# If the count exceeds a threshold (default: 20), blocks execution.
# This catches the exploit well before the 50-command limit.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

THRESHOLD=${CC_SUBCOMMAND_LIMIT:-20}

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Count subcommands: split on ; && ||
# Use tr to normalize separators, then count
SUBCOMMAND_COUNT=$(echo "$CMD" | tr ';' '\n' | tr '&' '\n' | tr '|' '\n' | grep -c '[^ ]' 2>/dev/null || echo 1)

if [ "$SUBCOMMAND_COUNT" -gt "$THRESHOLD" ]; then
    echo "BLOCKED: Command contains $SUBCOMMAND_COUNT subcommands (limit: $THRESHOLD)." >&2
    echo "  Claude Code ignores deny rules after 50 subcommands (CVE disclosure)." >&2
    echo "  This hook blocks at $THRESHOLD to prevent security bypass." >&2
    echo "  Override: CC_SUBCOMMAND_LIMIT=100 (not recommended)" >&2
    exit 2
fi

# Also detect the specific attack pattern: many "true" or ":" no-ops
NOOP_COUNT=$(echo "$CMD" | grep -oE '\btrue\b|^:|;\s*:' | wc -l 2>/dev/null || echo 0)
if [ "$NOOP_COUNT" -gt 10 ]; then
    echo "BLOCKED: Suspicious pattern — $NOOP_COUNT no-op commands detected." >&2
    echo "  This resembles the subcommand-chain attack (50x true + dangerous cmd)." >&2
    exit 2
fi

exit 0
