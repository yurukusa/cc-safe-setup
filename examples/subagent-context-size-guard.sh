#!/bin/bash
# subagent-context-size-guard.sh — Warn on thin subagent prompts
#
# Solves: Subagents get spawned with minimal context, leading to
#         poor results because they lack necessary background (#40929).
#         The parent agent assumes shared context, but each subagent
#         starts fresh.
#
# How it works: Checks Agent tool's prompt parameter length.
#   If under 100 characters, warns that the prompt may be too thin
#   for a standalone agent to work effectively.
#
# TRIGGER: PreToolUse
# MATCHER: "Agent"

set -euo pipefail
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)

[ -z "$PROMPT" ] && exit 0

LEN=${#PROMPT}
if [ "$LEN" -lt 100 ]; then
  echo "WARNING: Agent prompt is only ${LEN} chars. Subagents start with zero context — include enough background for them to work independently." >&2
fi
exit 0
