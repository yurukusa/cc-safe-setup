#!/bin/bash
# gitignore-auto-add.sh — Suggest .gitignore entries for common patterns
#
# Prevents: Committing build artifacts, cache dirs, env files.
#           When Claude creates new directories or files that should
#           be gitignored, this hook warns.
#
# TRIGGER: PostToolUse
# MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check mkdir and touch commands
echo "$COMMAND" | grep -qE '^\s*(mkdir|touch)\s' || exit 0

# Patterns that should typically be gitignored
GITIGNORE_PATTERNS="node_modules|__pycache__|\.cache|dist/|build/|\.next|\.nuxt|\.env\.|coverage|\.pytest_cache|\.mypy_cache|\.tox|\.venv|venv|\.eggs"

# Extract the target path
TARGET=$(echo "$COMMAND" | awk '{print $NF}')

if echo "$TARGET" | grep -qiE "$GITIGNORE_PATTERNS"; then
  if ! git check-ignore -q "$TARGET" 2>/dev/null; then
    echo "TIP: '$TARGET' should probably be in .gitignore." >&2
  fi
fi

exit 0
