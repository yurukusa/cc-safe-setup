#!/bin/bash
# cwd-drift-detector.sh — Warn when destructive commands run outside project root
#
# Solves: Claude frequently loses track of which directory
#         it is in, risking destructive commands in the wrong
#         location (#1669). git reset --hard in the wrong
#         directory can destroy unrelated work.
#
# How it works: For destructive commands (git reset, rm -rf,
#   git clean, git checkout -- .), checks if the current
#   directory looks like a project root (has .git, package.json,
#   etc). Warns if it doesn't.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail
INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check destructive commands
if ! echo "$COMMAND" | grep -qE '(git\s+(reset|clean|checkout\s+--|push\s+--force)|rm\s+-rf|DROP\s+TABLE|DROP\s+DATABASE)'; then
  exit 0
fi

# Check if we're in a project root
CWD=$(pwd)
IS_PROJECT=false

for marker in .git package.json Cargo.toml go.mod pyproject.toml Makefile; do
  if [ -e "$CWD/$marker" ]; then
    IS_PROJECT=true
    break
  fi
done

if [ "$IS_PROJECT" = false ]; then
  echo "WARNING: Destructive command detected outside project root." >&2
  echo "  CWD: $CWD" >&2
  echo "  Command: $(echo "$COMMAND" | head -c 100)" >&2
  echo "  No project markers (.git, package.json, etc) found." >&2
  echo "  Verify you are in the correct directory." >&2
fi

exit 0
