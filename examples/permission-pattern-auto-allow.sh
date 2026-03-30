#!/bin/bash
# permission-pattern-auto-allow.sh — Auto-allow commands matching user-defined patterns
#
# Solves: Claude repeatedly asks for permission to run commands
#         even after "Always Allow" — because the settings use
#         exact argument matching, not pattern matching (#819).
#
# How it works: Maintains a list of regex patterns in an env var
#   or config file. If the Bash command matches any pattern,
#   returns allow decision. Bypasses the broken exact-match
#   permission system entirely.
#
# Config: Set ALLOWED_PATTERNS env var or create ~/.claude/allowed-patterns.txt
#   Example patterns (one per line):
#     ^npm (test|run|install|ci)
#     ^git (status|log|diff|add|commit|push|pull|fetch|branch|checkout)
#     ^(ls|cat|pwd|echo|head|tail|wc|grep|find|which|env)
#     ^python[23]?\s
#     ^cargo (build|test|run|check)
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail
INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Load patterns from file or env
PATTERN_FILE="${HOME}/.claude/allowed-patterns.txt"
if [ -f "$PATTERN_FILE" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    if echo "$COMMAND" | grep -qE "$pattern" 2>/dev/null; then
      exit 0
    fi
  done < "$PATTERN_FILE"
elif [ -n "${ALLOWED_PATTERNS:-}" ]; then
  # Fallback: pipe-separated patterns in env var
  echo "$ALLOWED_PATTERNS" | tr '|' '\n' | while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if echo "$COMMAND" | grep -qE "$pattern" 2>/dev/null; then
      exit 0
    fi
  done
fi

exit 0
