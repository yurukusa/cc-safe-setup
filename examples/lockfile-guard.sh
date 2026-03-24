#!/bin/bash
# ================================================================
# lockfile-guard.sh — Warn when lockfiles are modified unexpectedly
# ================================================================
# PURPOSE:
#   Claude sometimes runs npm install or pip install that modifies
#   lockfiles (package-lock.json, yarn.lock, Cargo.lock, etc.)
#   without the user intending a dependency change. This hook warns
#   when a lockfile appears in staged changes.
#
# TRIGGER: PreToolUse  MATCHER: "Bash"
# ================================================================

COMMAND=$(cat | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only check git commit
echo "$COMMAND" | grep -qE '^\s*git\s+(commit|add)' || exit 0

# Check for lockfile changes
LOCKFILES=$(git diff --cached --name-only 2>/dev/null | grep -E '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|Gemfile\.lock|poetry\.lock|composer\.lock|go\.sum)' 2>/dev/null)

if [ -n "$LOCKFILES" ]; then
    COUNT=$(echo "$LOCKFILES" | wc -l)
    echo "WARNING: $COUNT lockfile(s) modified:" >&2
    echo "$LOCKFILES" | sed 's/^/  /' >&2
    echo "Verify the dependency change was intentional." >&2
fi

exit 0
