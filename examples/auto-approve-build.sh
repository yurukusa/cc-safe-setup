#!/bin/bash
# auto-approve-build.sh — Auto-approve build and test commands
#
# Solves: Permission prompts for npm/yarn/pnpm build/test/lint commands
#         that slow down autonomous workflows
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/auto-approve-build.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" != "Bash" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Auto-approve safe build/test/lint commands
if echo "$CMD" | grep -qE '^\s*(npm|yarn|pnpm|bun|npx)\s+(run\s+)?(build|test|lint|check|typecheck|format|dev|start|ci)'; then
    echo '{"decision":"approve"}'
    exit 0
fi

# Auto-approve cargo/go/make build commands
if echo "$CMD" | grep -qE '^\s*(cargo\s+(build|test|check|clippy|fmt)|go\s+(build|test|vet|fmt)|make\s+(build|test|check|lint))'; then
    echo '{"decision":"approve"}'
    exit 0
fi

# Auto-approve python test/lint
if echo "$CMD" | grep -qE '^\s*(python|python3)\s+(-m\s+)?(pytest|unittest|mypy|ruff|black|isort|flake8)'; then
    echo '{"decision":"approve"}'
    exit 0
fi

exit 0
