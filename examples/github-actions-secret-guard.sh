#!/bin/bash
# github-actions-secret-guard.sh — Prevent hardcoded secrets in GitHub Actions workflows
#
# Solves: Claude writes API keys, tokens, or passwords directly into
#         .github/workflows/*.yml files instead of using ${{ secrets.NAME }}.
#         These get committed and pushed to public/private repos.
#
# How it works: PostToolUse hook on Edit/Write that checks if the target
#   is a GitHub Actions workflow file, then scans for patterns that look
#   like hardcoded secrets instead of ${{ secrets.* }} references.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in Edit|Write) ;; *) exit 0 ;; esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Only check GitHub Actions workflow files
case "$FILE" in
    .github/workflows/*.yml|.github/workflows/*.yaml) ;;
    */.github/workflows/*.yml|*/.github/workflows/*.yaml) ;;
    *) exit 0 ;;
esac

[ -f "$FILE" ] || exit 0

# Check for hardcoded secret patterns (not using ${{ secrets.* }})
ISSUES=""

# API keys / tokens in env or with: blocks
if grep -nE '(APIKEY|API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY)\s*[:=]\s*["\x27]?[A-Za-z0-9+/=_-]{20,}' "$FILE" 2>/dev/null | grep -v '\${{' | head -3 | grep -q .; then
    ISSUES="${ISSUES}Hardcoded API key/token found (use \${{ secrets.NAME }} instead)\n"
fi

# Bearer tokens
if grep -nE 'Bearer\s+[A-Za-z0-9._-]{20,}' "$FILE" 2>/dev/null | grep -v '\${{' | head -1 | grep -q .; then
    ISSUES="${ISSUES}Hardcoded Bearer token found\n"
fi

# AWS credentials
if grep -nE 'AKIA[0-9A-Z]{16}' "$FILE" 2>/dev/null | head -1 | grep -q .; then
    ISSUES="${ISSUES}AWS access key ID found in workflow\n"
fi

if [ -n "$ISSUES" ]; then
    echo "WARNING: Potential secrets in GitHub Actions workflow:" >&2
    echo "  File: $FILE" >&2
    echo -e "  $ISSUES" >&2
    echo "  Use \${{ secrets.NAME }} instead of hardcoded values." >&2
    echo "  Add secrets via: gh secret set NAME --body 'value'" >&2
fi

exit 0
