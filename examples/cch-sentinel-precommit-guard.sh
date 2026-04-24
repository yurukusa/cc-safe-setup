#!/usr/bin/env bash
# cch-sentinel-precommit-guard.sh — native sentinel content guard (Incident 3)
# Why: The standalone Bun Claude Code binary substitutes the literal string
#      `cch=00000` at the native layer — below anything the JavaScript hook
#      surface can intercept. Committing the literal into a file Claude reads
#      triggers cache invalidation patterns and a 10-20x cost multiplier on
#      affected sessions. This guard refuses the commit before the string
#      ever reaches Claude's working set.
# Event: git pre-commit (NOT a Claude Code hook)
# Install:
#   cp examples/cch-sentinel-precommit-guard.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
# Or, to combine with existing pre-commit logic:
#   append `bash path/to/cch-sentinel-precommit-guard.sh || exit 1` to your
#   existing .git/hooks/pre-commit.
#
# False positive: documentation that writes ABOUT the sentinel bug will trip
# this guard. Bypass via `git commit --no-verify` once, or exclude docs paths:
#   CCH_ALLOW_PATHS="docs/|README" bash .git/hooks/pre-commit

set -u

# Allow opt-out for docs that discuss the bug (the Postmortems book itself
# needs this escape hatch).
ALLOW_PATHS="${CCH_ALLOW_PATHS:-}"

if [ -n "$ALLOW_PATHS" ]; then
  # Check only files that do not match the allowlist regex.
  FILES_TO_CHECK=$(git diff --cached --name-only | grep -Ev "$ALLOW_PATHS" || true)
  if [ -z "$FILES_TO_CHECK" ]; then
    exit 0
  fi
  MATCH=$(git diff --cached -- $FILES_TO_CHECK 2>/dev/null | grep -n 'cch=00000' || true)
else
  MATCH=$(git diff --cached 2>/dev/null | grep -n 'cch=00000' || true)
fi

if [ -n "$MATCH" ]; then
  echo "refusing commit: literal cch=00000 found in staged diff" >&2
  echo "this string triggers native sentinel substitution in the Bun Claude Code binary" >&2
  echo "see cc-safe-setup Incident 3 or set CCH_ALLOW_PATHS for documentation writes" >&2
  echo "--- matching lines ---" >&2
  printf '%s\n' "$MATCH" | head -5 >&2
  exit 1
fi

exit 0
