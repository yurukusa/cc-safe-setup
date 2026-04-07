#!/bin/bash
# bash-heuristic-approver.sh — Auto-approve bash safety heuristic prompts
#
# Solves: Safety heuristic prompts cannot be suppressed (#30435, 30 reactions)
#         Claude Code fires prompts for common patterns like:
#         - $() command substitution
#         - Backtick substitution
#         - Newlines in commands (for loops, multi-step scripts)
#         - Quote characters in comments
#         - ANSI-C quoting
#         These cannot be bypassed with permissions.allow or acceptEdits.
#
# This PermissionRequest hook detects heuristic-triggered prompts and
# auto-approves them when the base command is in a safe list.
#
# TRIGGER: PermissionRequest
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/bash-heuristic-approver.sh" }]
#     }]
#   }
# }

INPUT=$(cat)

# Detect safety heuristic prompts by their characteristic messages
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)
[ -z "$MESSAGE" ] && exit 0

# Match known heuristic warning patterns
HEURISTIC_PATTERNS="command substitution|backtick|can desync quote|potential bypass|can hide characters|quoted characters|newline|ANSI.C quot"

if ! echo "$MESSAGE" | grep -qiE "$HEURISTIC_PATTERNS"; then
  # Not a heuristic prompt — pass through
  exit 0
fi

# Extract the command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Safe base commands — only auto-approve for known-safe tools
SAFE_COMMANDS="git|npm|npx|bun|yarn|pnpm|docker|make|cargo|go|pip|python3|node|tsc|eslint|prettier|jest|vitest|pytest|gh|curl|wget|rsync|tar|zip|unzip|find|grep|sed|awk|cat|echo|ls|mkdir|cp|mv|chmod|wc|sort|head|tail|jq|python3"

# Extract first meaningful command (skip env vars, cd, whitespace)
BASE_CMD=$(echo "$COMMAND" | tr '\n' ' ' | sed 's/^[[:space:]]*//' | sed 's/^[A-Z_]*=[^ ]* //' | sed 's/^cd [^&;]* *[&;]* *//' | awk '{print $1}' | sed 's|.*/||')

if echo "$BASE_CMD" | grep -qE "^($SAFE_COMMANDS)$"; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
  exit 0
fi

# Unknown base command — let the prompt through for safety
exit 0
