#!/bin/bash
# bash-safety-auto-deny.sh — Auto-deny commands that trigger safety prompts
#
# Solves: Users want "auto-deny" instead of "prompt" for risky commands (#28993).
#         Currently Claude's safety heuristic prompts the user. This hook
#         blocks the command outright, forcing Claude to reformulate.
#
# How it works: PreToolUse hook on Bash that detects patterns the built-in
#   safety system would flag, and blocks them with exit 2 instead of
#   prompting. Claude learns to use safer alternatives.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Patterns that trigger built-in safety prompts
# 1. Pipe to bash/sh (command injection risk)
if echo "$COMMAND" | grep -qE '\|\s*(bash|sh|zsh)\b'; then
  echo "BLOCKED: Piping to shell interpreter detected." >&2
  echo "Reformulate without piping to bash/sh." >&2
  exit 2
fi

# 2. curl/wget piped to execution
if echo "$COMMAND" | grep -qE '(curl|wget)\s.*\|\s*(bash|sh|python|node|perl)'; then
  echo "BLOCKED: Remote code execution pattern detected." >&2
  echo "Download the file first, review it, then execute separately." >&2
  exit 2
fi

# 3. eval with variable expansion
if echo "$COMMAND" | grep -qE '\beval\s'; then
  echo "BLOCKED: eval detected. Use direct commands instead." >&2
  exit 2
fi

# 4. Nested command substitution in dangerous positions
if echo "$COMMAND" | grep -qE '(rm|mv|cp|chmod|chown)\s.*\$\('; then
  echo "BLOCKED: Command substitution in destructive command." >&2
  echo "Expand the subcommand first, verify the result, then run." >&2
  exit 2
fi

# 5. Globbed rm (rm *.* or rm -rf *)
if echo "$COMMAND" | grep -qE 'rm\s+.*\*'; then
  echo "BLOCKED: Wildcard deletion detected." >&2
  echo "List the files first (ls), verify, then delete specific files." >&2
  exit 2
fi

exit 0
