#!/bin/bash
# askuserquestion-autonomy-gate.sh — Block AskUserQuestion in autonomy mode
#
# Solves: Claude blocking /goal mode or overnight autonomous runs indefinitely
# by invoking AskUserQuestion to ask the operator whether to proceed
# (anthropics/claude-code#61337). Recognition-without-arrest at the
# PreToolUse-AskUserQuestion lifecycle event.
#
# The model recognizes an autonomous-operation constraint
# (e.g. "operate autonomously, never ask questions"), articulates a reason
# why the current task is hard enough to warrant asking anyway, then invokes
# AskUserQuestion. With no operator present, the session blocks indefinitely.
#
# This hook arrests AskUserQuestion calls when CC_AUTONOMY_MODE=1 is set.
# The stderr message gives the model a defensible next action so it does not
# loop retrying the same blocked tool call.
#
# Modes:
#   CC_AUTONOMY_MODE=0 (default): advisory only, no blocking
#   CC_AUTONOMY_MODE=1: blocking, exit 2, structured stderr explanation
#   CC_AUTONOMY_MODE_RECEIPT_DIR: directory for blocked-call receipts
#     (default: ~/.claude/receipts)
#
# Usage: Add to settings.json as a PreToolUse hook matching AskUserQuestion
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "AskUserQuestion",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/askuserquestion-autonomy-gate.sh"
#       }]
#     }]
#   }
# }
#
# Then in any shell that runs /goal overnight or autonomous tasks:
#   export CC_AUTONOMY_MODE=1
#
# TRIGGER: PreToolUse  MATCHER: "AskUserQuestion"

set -u

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only act on AskUserQuestion tool calls
[[ "$TOOL" != "AskUserQuestion" ]] && exit 0

# Advisory mode by default: observe but do not block
if [[ "${CC_AUTONOMY_MODE:-0}" != "1" ]]; then
  exit 0
fi

# In autonomy mode: write a receipt, then block
RECEIPT_DIR="${CC_AUTONOMY_MODE_RECEIPT_DIR:-$HOME/.claude/receipts}"
mkdir -p "$RECEIPT_DIR" 2>/dev/null || true
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RECEIPT_FILE="$RECEIPT_DIR/autonomy-blocked-$(date -u +%Y-%m-%d).jsonl"

# Extract question summary for the receipt (hash only — never the full prompt
# text, to keep PHI-safe per cc-safe-setup convention).
QUESTION=$(echo "$INPUT" | jq -r '.tool_input.question // .tool_input.prompt // empty' 2>/dev/null)
QUESTION_HASH=""
QUESTION_LEN=0
if [[ -n "$QUESTION" ]]; then
  QUESTION_HASH=$(printf '%s' "$QUESTION" | sha256sum 2>/dev/null | awk '{print $1}')
  QUESTION_LEN=$(printf '%s' "$QUESTION" | wc -c | tr -d ' ')
fi

# Append the receipt (best-effort; never block on receipt failure)
{
  printf '{"ts":"%s","event":"askuserquestion_blocked","question_hash":"%s","question_length":%s,"autonomy_mode":1}\n' \
    "$TS" "$QUESTION_HASH" "$QUESTION_LEN"
} >> "$RECEIPT_FILE" 2>/dev/null || true

# Block the tool call with a stderr message that gives the model a next action
cat >&2 <<'EOF'
AskUserQuestion is blocked in autonomy mode (CC_AUTONOMY_MODE=1).
The operator is not present and cannot answer.

You must either (a) make a defensible default choice and document it inline,
or (b) write a stop-with-explanation note in the working memo (e.g.
./.claude/autonomy-blocks.md) and proceed to the next task in the goal queue.

Do not retry AskUserQuestion in this turn. The same call will be blocked again.
EOF

exit 2
