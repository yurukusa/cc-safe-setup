#!/bin/bash
# uncommitted-work-shield.sh — Auto-stash before destructive git operations
#
# Solves: Git operations destroying uncommitted work (#34327, #33850, #37150).
#         Users lost days of work from git reset/checkout/clean.
#         Unlike uncommitted-work-guard (which blocks), this hook SAVES work.
#
# How it works: PreToolUse hook on Bash that detects destructive git
#   commands and auto-stashes uncommitted changes before allowing them.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check destructive git commands
DESTRUCTIVE_GIT='git\s+(reset\s+--hard|checkout\s+--|clean\s+-[fd]|stash\s+drop|stash\s+clear)'

if ! echo "$COMMAND" | grep -qE "$DESTRUCTIVE_GIT"; then
  exit 0
fi

# Check if there are uncommitted changes
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  # Auto-stash with timestamp
  STASH_MSG="auto-shield-$(date +%Y%m%d-%H%M%S)"
  git stash push -m "$STASH_MSG" 2>/dev/null || true
  echo "SHIELDED: Uncommitted changes saved to stash '$STASH_MSG'." >&2
  echo "Restore with: git stash pop" >&2
fi

# Allow the command to proceed (changes are saved)
exit 0
