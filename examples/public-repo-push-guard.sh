#!/bin/bash
# public-repo-push-guard.sh — Block pushing proprietary code to public repos
#
# Solves: Accidental exposure of private code to public repositories (#29225).
#         Claude pushes code containing internal paths, strategy files, or
#         proprietary patterns to a public GitHub repo.
#
# How it works: PreToolUse hook on Bash that detects git push commands,
#   checks if the remote repo is public via gh API, then scans staged
#   files against a configurable blocklist.
#
# Configuration: CC_PRIVATE_PATTERNS (colon-separated glob patterns)
#   Default: "internal/:strategies/:*.secret.*:*.private.*"
#
# TRIGGER: PreToolUse
# MATCHER: "Bash"

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git push
if ! echo "$COMMAND" | grep -qE '^\s*git\s+push\b'; then
  exit 0
fi

# Get remote URL
REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
[ -z "$REMOTE" ] && exit 0

# Extract owner/repo from URL
REPO=$(echo "$REMOTE" | sed -E 's|.*github\.com[:/]||; s|\.git$||')
[ -z "$REPO" ] && exit 0

# Check visibility (requires gh CLI)
if command -v gh &>/dev/null; then
  VISIBILITY=$(gh repo view "$REPO" --json visibility --jq '.visibility' 2>/dev/null || echo "UNKNOWN")
  if [ "$VISIBILITY" = "PUBLIC" ]; then
    # Check staged files against private patterns
    PATTERNS="${CC_PRIVATE_PATTERNS:-internal/:strategies/:*.secret.*:*.private.*}"
    STAGED=$(git diff --cached --name-only 2>/dev/null || echo "")

    IFS=':' read -ra PATS <<< "$PATTERNS"
    for pat in "${PATS[@]}"; do
      MATCH=$(echo "$STAGED" | grep -E "$pat" | head -1)
      if [ -n "$MATCH" ]; then
        echo "BLOCKED: Pushing to PUBLIC repo '$REPO' with private file pattern." >&2
        echo "File: $MATCH matches pattern: $pat" >&2
        echo "Remove private files from staging or push to a private repo." >&2
        exit 2
      fi
    done
  fi
fi

exit 0
