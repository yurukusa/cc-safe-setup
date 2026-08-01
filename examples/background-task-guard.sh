#!/bin/bash
# background-task-guard.sh — Audit background Bash execution
#
# Solves: run_in_background:true on Bash tool skips the approval
# prompt, allowing dangerous commands to execute without user
# confirmation. (#46950)
#
# How it works: Checks if a Bash command is running in background
# mode. If the command matches dangerous patterns (destructive ops,
# network access, file deletion), blocks it. Background execution
# should only be used for safe, read-only operations.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

# Without jq, the parse below silently yields empty and this hook stops
# guarding - with no error anywhere. Say so. We deliberately do not exit
# here: blocking would halt every tool call, and exiting 0 would change
# the behaviour of guards that do not depend on the parsed value.
if ! command -v jq >/dev/null 2>&1; then
  _nojq_warned="/tmp/cc-nojq-warned-background-task-guard-$PPID"
  [ -f "$_nojq_warned" ] || {
    echo "WARNING [background-task-guard]: jq not found - this hook cannot inspect tool calls and is NOT protecting you. Install jq." >&2
    : > "$_nojq_warned"
  }
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Check if this is a background execution
# Note: run_in_background is in tool_input for Bash
IS_BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
[ "$IS_BG" != "true" ] && exit 0

# Background execution detected — apply strict safety rules
# Only allow read-only commands in background

# Block destructive operations
if echo "$CMD" | grep -qiE '\brm\s+-rf\b|\bgit\s+(push|reset|clean|checkout\s+--)\b|\bchmod\b|\bchown\b'; then
    echo "BLOCKED: Destructive command not allowed in background mode." >&2
    echo "  Background tasks skip approval prompts — run this in foreground." >&2
    exit 2
fi

# Block network writes
if echo "$CMD" | grep -qiE 'curl\s+.*-X\s*(POST|PUT|PATCH|DELETE)|curl\s+.*--data|curl\s+.*-d\s|wget\s+.*--post'; then
    echo "BLOCKED: Network write operation not allowed in background mode." >&2
    echo "  Background tasks skip approval prompts — run this in foreground." >&2
    exit 2
fi

# Block file writes to sensitive locations
if echo "$CMD" | grep -qiE '>\s*(/etc/|/usr/|/var/|~/.ssh/|~/.gnupg/|~/.claude/settings)'; then
    echo "BLOCKED: Write to sensitive path not allowed in background mode." >&2
    echo "  Background tasks skip approval prompts — run this in foreground." >&2
    exit 2
fi

# Block process killing
if echo "$CMD" | grep -qiE '\bkill\b|\bkillall\b|\bpkill\b'; then
    echo "BLOCKED: Process termination not allowed in background mode." >&2
    exit 2
fi

exit 0
