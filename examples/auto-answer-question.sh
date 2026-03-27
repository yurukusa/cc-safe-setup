#!/bin/bash
# auto-answer-question.sh — Auto-answer AskUserQuestion for headless/autonomous mode
#
# TRIGGER: PreToolUse
# MATCHER: AskUserQuestion
#
# v2.1.85+: PreToolUse hooks can satisfy AskUserQuestion by returning
# updatedInput alongside permissionDecision: "allow".
#
# Usage:
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "AskUserQuestion",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/auto-answer-question.sh"
#       }]
#     }]
#   }
# }
#
# Dangerous operations → answer NO
# Safe operations (test, build, lint) → answer YES
# Unknown questions → pass through to human

INPUT=$(cat)
QUESTION=$(echo "$INPUT" | jq -r '.tool_input.question // empty' 2>/dev/null)
[ -z "$QUESTION" ] && exit 0

# Log all auto-answered questions for audit
LOG_DIR="${HOME}/.claude/audit"
mkdir -p "$LOG_DIR"
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') Q: $QUESTION" >> "$LOG_DIR/auto-answers.log"

# Dangerous operations → always NO
if echo "$QUESTION" | grep -qiE 'delete|削除|drop|truncate|destroy|remove.*all|wipe|reset.*hard|force.*push|rm -rf'; then
    jq -n --arg q "$QUESTION" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: { question: $q, answer: "No. This operation is too risky for unattended mode." }
        }
    }'
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') A: NO (dangerous)" >> "$LOG_DIR/auto-answers.log"
    exit 0
fi

# Safe operations → always YES
if echo "$QUESTION" | grep -qiE 'test|テスト|build|ビルド|lint|format|check|確認|verify'; then
    jq -n --arg q "$QUESTION" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: { question: $q, answer: "Yes, proceed." }
        }
    }'
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') A: YES (safe op)" >> "$LOG_DIR/auto-answers.log"
    exit 0
fi

# Unknown → pass through to human
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') A: PASS (unknown)" >> "$LOG_DIR/auto-answers.log"
exit 0
