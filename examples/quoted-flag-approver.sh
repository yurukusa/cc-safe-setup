#!/bin/bash
# quoted-flag-approver.sh — Auto-approve commands with quoted flag values
#
# Solves: "Command contains quoted characters in flag names" false positives
#         (#27957 — 70 reactions, breaks agentic workflows)
#
# After a Claude Code update, normal commands like:
#   git commit -m "fix bug"
#   bun run build --flag "value"
# trigger a confirmation prompt even when they match allowlist patterns.
#
# This PermissionRequest hook auto-approves these prompts when:
# 1. The base command is in a safe list
# 2. The only "issue" is quoted characters in flag values
#
# TRIGGER: PermissionRequest
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "PermissionRequest": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/quoted-flag-approver.sh" }]
#     }]
#   }
# }

INPUT=$(cat)

# Only handle "quoted characters in flag names" prompts
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty' 2>/dev/null)
echo "$MESSAGE" | grep -qi "quoted characters in flag" || exit 0

# Extract the command being checked
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Safe base commands — customize for your project
SAFE_COMMANDS="git|npm|npx|bun|yarn|pnpm|docker|make|cargo|go|pip|python3|node|tsc|eslint|prettier|jest|vitest|pytest|curl|wget|rsync|tar|zip|unzip|cp|mv|mkdir|cat|echo|grep|find|ls|chmod|sed|awk"

# Extract base command (first word, ignoring env vars and path)
BASE_CMD=$(echo "$COMMAND" | sed 's/^[A-Z_]*=[^ ]* //' | awk '{print $1}' | sed 's|.*/||')

if echo "$BASE_CMD" | grep -qE "^($SAFE_COMMANDS)$"; then
  echo '{"permissionDecision":"allow"}'
  exit 0
fi

# Unknown command — let the prompt through
exit 0
