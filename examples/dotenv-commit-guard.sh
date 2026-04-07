#!/bin/bash
# dotenv-commit-guard.sh — Prevent committing .env files with secrets
#
# Solves: Claude adding .env files to git staging and committing them.
#         Even with .gitignore, Claude can `git add -f .env` to force-add.
#
# How it works: PreToolUse hook on Bash that detects git add/commit
#   commands including .env files and blocks them.
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Check for git add with .env files
# Allow .env.example, .env.sample, .env.template
if echo "$COMMAND" | grep -qE 'git\s+add\s+.*\.env\.(example|sample|template)'; then
    exit 0
fi
if echo "$COMMAND" | grep -qE 'git\s+add\s+.*\.env'; then
    echo "BLOCKED: Adding .env file to git staging." >&2
    echo "  .env files contain secrets and should not be committed." >&2
    echo "  Use .env.example with placeholder values instead." >&2
    exit 2
fi

# Check for git add -f/--force (bypasses .gitignore — can stage secrets)
# GitHub Issue anthropics/claude-code#44730: auto-mode used git add -f to
# force-add .gitignore'd secret files, exposing credentials in a commit.
if echo "$COMMAND" | grep -qE 'git\s+add\s+.*(-f|--force)\b'; then
    echo "BLOCKED: 'git add --force' bypasses .gitignore and can stage secret files." >&2
    echo "  Use 'git add <specific-file>' without --force instead." >&2
    exit 2
fi

# Check for git add -A/--all that might include .env
if echo "$COMMAND" | grep -qE 'git\s+add\s+(-A|--all)\b'; then
    if [ -f ".env" ] || [ -f ".env.local" ] || [ -f ".env.production" ]; then
        if ! git check-ignore -q .env 2>/dev/null; then
            echo "WARNING: 'git add -A' with .env file not in .gitignore." >&2
            echo "  Add .env to .gitignore before staging all files." >&2
        fi
    fi
fi

exit 0
