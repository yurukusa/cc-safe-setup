#!/bin/bash
# ================================================================
# fish-shell-wrapper.sh — Run Bash tool commands in fish shell
# ================================================================
# PURPOSE:
#   Users who develop in fish lose PATH, aliases, and env vars because
#   Claude Code's Bash tool uses the system default shell (usually zsh/bash).
#   This hook wraps commands in `fish -c '...'` so they execute in fish.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"
#
# See: https://github.com/anthropics/claude-code/issues/7490
# ================================================================

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Skip if already wrapped in fish
echo "$COMMAND" | grep -q '^fish -c' && exit 0

# Skip simple builtins that work identically in any shell
echo "$COMMAND" | grep -qE '^\s*(cd|echo|cat|ls|pwd|true|false|test|mkdir|touch|rm|cp|mv)\b' && exit 0

# Escape single quotes for fish -c '...'
ESCAPED=$(printf '%s' "$COMMAND" | sed "s/'/'\\\\''/g")

jq -n --arg cmd "fish -c '$ESCAPED'" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: { command: $cmd }
  }
}'

exit 0
