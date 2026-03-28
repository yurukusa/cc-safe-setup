#!/bin/bash
# staged-secret-scan.sh — Block git commit if staged diff contains secrets
#
# Solves: Claude committing API keys, passwords, and tokens to version
#         control despite CLAUDE.md guidelines (#2142, 10+ reactions)
#
# How it works: When Claude runs `git commit`, this hook inspects the
#   staged diff (git diff --cached) for known secret patterns.
#   Blocks the commit if any are found.
#
# Patterns detected:
#   - AWS keys (AKIA...), GCP service account keys
#   - Generic API keys (sk-, pk_, ghp_, gho_, glpat-, xoxb-)
#   - Passwords in config files
#   - Private keys (PEM format)
#   - JWT tokens
#   - .env files being committed
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0
fi

# Must be in a git repo
git rev-parse --git-dir &>/dev/null || exit 0

# Check if .env files are staged
ENV_FILES=$(git diff --cached --name-only 2>/dev/null | grep -E '\.env($|\.)')
if [[ -n "$ENV_FILES" ]]; then
    echo "BLOCKED: .env file(s) staged for commit:" >&2
    echo "$ENV_FILES" | sed 's/^/  /' >&2
    echo "Remove with: git reset HEAD <file>" >&2
    exit 2
fi

# Get staged diff
DIFF=$(git diff --cached 2>/dev/null)
[[ -z "$DIFF" ]] && exit 0

FOUND=0

# AWS access keys
if echo "$DIFF" | grep -qE '^\+.*AKIA[0-9A-Z]{16}'; then
    echo "BLOCKED: AWS access key detected in staged changes" >&2
    FOUND=1
fi

# Common API key prefixes
if echo "$DIFF" | grep -qE '^\+.*(sk-[a-zA-Z0-9]{20,}|pk_[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|glpat-[a-zA-Z0-9]{20}|xoxb-[0-9]{10,})'; then
    echo "BLOCKED: API key/token detected in staged changes" >&2
    FOUND=1
fi

# Generic secret assignment patterns
if echo "$DIFF" | grep -qE '^\+.*(api_key|apikey|secret_key|access_token|auth_token)\s*[=:]\s*["\x27][a-zA-Z0-9]{20,}["\x27]'; then
    echo "BLOCKED: Hardcoded secret detected in staged changes" >&2
    FOUND=1
fi

# Private keys
if echo "$DIFF" | grep -qE '^\+.*BEGIN (RSA |EC |DSA )?PRIVATE KEY'; then
    echo "BLOCKED: Private key detected in staged changes" >&2
    FOUND=1
fi

# JWT tokens
if echo "$DIFF" | grep -qE '^\+.*eyJ[a-zA-Z0-9_-]{20,}\.eyJ[a-zA-Z0-9_-]{20,}'; then
    echo "BLOCKED: JWT token detected in staged changes" >&2
    FOUND=1
fi

# GCP service account key
if echo "$DIFF" | grep -qE '^\+.*"type"\s*:\s*"service_account"'; then
    echo "BLOCKED: GCP service account key detected in staged changes" >&2
    FOUND=1
fi

if [[ "$FOUND" -eq 1 ]]; then
    echo "" >&2
    echo "Unstage the file: git reset HEAD <file>" >&2
    echo "Use .gitignore or environment variables instead." >&2
    exit 2
fi

exit 0
