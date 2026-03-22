#!/bin/bash
# auto-approve-python.sh — Auto-approve Python development commands
#
# Solves: Permission prompts for pytest, mypy, ruff, black, isort
#         that slow down autonomous Python development
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-approve-python.sh" }]
#     }]
#   }
# }

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Python test runners
if echo "$COMMAND" | grep -qE '^\s*(pytest|python\s+-m\s+pytest|python\s+-m\s+unittest)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Python test auto-approved"}}'
    exit 0
fi

# Linters and formatters
if echo "$COMMAND" | grep -qE '^\s*(ruff\s+(check|format)|black\s|isort\s|flake8\s|pylint\s|mypy\s|pyright\s)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Python lint/format auto-approved"}}'
    exit 0
fi

# Package management (read-only)
if echo "$COMMAND" | grep -qE '^\s*(pip\s+list|pip\s+show|pip\s+freeze|pipdeptree)(\s|$)'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"pip read-only auto-approved"}}'
    exit 0
fi

# Python syntax check
if echo "$COMMAND" | grep -qE '^\s*python3?\s+-m\s+py_compile\s'; then
    jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Python compile check auto-approved"}}'
    exit 0
fi

exit 0
