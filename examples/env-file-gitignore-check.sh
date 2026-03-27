#!/bin/bash
# env-file-gitignore-check.sh — Warn if .env is not in .gitignore
#
# Prevents: Accidental commit of .env files containing secrets.
#           Checks on session start if .env exists but .gitignore
#           doesn't exclude it.
#
# TRIGGER: Notification
# MATCHER: ""
#
# Usage:
# {
#   "hooks": {
#     "Notification": [{
#       "matcher": "",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/env-file-gitignore-check.sh" }]
#     }]
#   }
# }

# Only run once per session
MARKER="/tmp/cc-env-gitignore-$$"
[ -f "$MARKER" ] && exit 0

# Check if we're in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || { touch "$MARKER"; exit 0; }

# Check if .env exists
[ -f ".env" ] || { touch "$MARKER"; exit 0; }

# Check if .env is in .gitignore
if ! git check-ignore -q .env 2>/dev/null; then
  echo "WARNING: .env file exists but is not in .gitignore!" >&2
  echo "  Add '.env' to .gitignore to prevent accidental commit." >&2
  echo "  echo '.env' >> .gitignore" >&2
fi

touch "$MARKER"
exit 0
