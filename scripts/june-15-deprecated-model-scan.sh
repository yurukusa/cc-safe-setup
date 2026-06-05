#!/usr/bin/env bash
# june-15-deprecated-model-scan.sh — Find hardcoded Claude model IDs that
#   stop working on 2026-06-15 (and other retirement dates) before they break
#   your code or CI with a hard error.
#
# Why this exists: the 2026-06-15 Anthropic change is widely explained as a
#   *billing* change (programmatic usage moves to a separate credit pool). But
#   the same date also *retires two model IDs from the API*. After retirement,
#   a request using a retired model ID returns a hard error (HTTP 404,
#   not_found_error) — your app or CI breaks, regardless of billing. The fix is
#   mechanical: bump the hardcoded ID to its replacement. This script finds the
#   IDs for you so nothing 404s on the 15th.
#
# What this does: a read-only grep of the directory you run it from for
#   retired / soon-to-retire model ID strings, and prints each hit with its
#   replacement. It does NOT modify any file, run any tool, or send any network
#   request. All checks are local string matches.
#
# Usage:
#   bash june-15-deprecated-model-scan.sh            # scan current directory
#   bash june-15-deprecated-model-scan.sh path/to/repo
#
# Exit codes: 0 = no retired/soon-to-retire IDs found; 1 = found at least one.
#   (CI-friendly: a non-zero exit fails the build so you fix it before the date.)
#
# Sources (Anthropic official model deprecations / migration guide):
#   https://platform.claude.com/docs/en/about-claude/models/overview
#   https://platform.claude.com/docs/en/about-claude/models/migration-guide
# License: MIT. Author: yurukusa.

set -uo pipefail

ROOT="${1:-.}"

# Each row: <deprecated-id>|<retirement-date>|<replacement-id>
# Dates and replacements verified against Anthropic's official model docs.
# The two 2026-06-15 IDs are the ones that retire *on the cliff date*.
DEPRECATIONS=(
  "claude-opus-4-20250514|2026-06-15|claude-opus-4-8"
  "claude-sonnet-4-20250514|2026-06-15|claude-sonnet-4-6"
  "claude-3-haiku-20240307|2026-04-19|claude-haiku-4-5"
  # Already retired (return 404 today) — listed so you catch leftovers:
  "claude-3-7-sonnet-20250219|2026-02-19 (retired)|claude-sonnet-4-6"
  "claude-3-5-haiku-20241022|2026-02-19 (retired)|claude-haiku-4-5"
  "claude-3-opus-20240229|2026-01-05 (retired)|claude-opus-4-8"
  "claude-3-5-sonnet-20241022|2025-10-28 (retired)|claude-sonnet-4-6"
  "claude-3-5-sonnet-20240620|2025-10-28 (retired)|claude-sonnet-4-6"
  "claude-3-sonnet-20240229|2025-07-21 (retired)|claude-sonnet-4-6"
)

# Directories that never contain your source — skip to keep output clean.
PRUNE='-path */node_modules/* -o -path */.git/* -o -path */dist/* -o -path */build/* -o -path */.venv/* -o -path */venv/* -o -path */__pycache__/*'

echo "June 15 (and beyond) deprecated Claude model ID scan"
echo "Scanning: $ROOT"
echo "----------------------------------------------------------------------"

found=0
cliff_found=0

for row in "${DEPRECATIONS[@]}"; do
  id="${row%%|*}"
  rest="${row#*|}"
  date="${rest%%|*}"
  repl="${rest#*|}"

  # Read-only: grep for the literal ID across text files. -I skips binaries.
  # shellcheck disable=SC2086
  hits="$(find "$ROOT" -type f \( $PRUNE \) -prune -o -type f -print 2>/dev/null \
            | xargs -r grep -InF -- "$id" 2>/dev/null)"

  if [ -n "$hits" ]; then
    found=1
    case "$date" in
      2026-06-15) cliff_found=1; flag="⛔ RETIRES ON THE 2026-06-15 CLIFF" ;;
      *retired*)  flag="⚠  ALREADY RETIRED (returns 404 today)" ;;
      *)          flag="⚠  retires $date" ;;
    esac
    echo
    echo "$flag"
    echo "  Deprecated: $id"
    echo "  Replace with: $repl"
    echo "  Found in:"
    echo "$hits" | sed 's/^/    /'
  fi
done

echo
echo "----------------------------------------------------------------------"
if [ "$found" -eq 0 ]; then
  echo "✅ No retired or soon-to-retire model IDs found. Nothing breaks on 2026-06-15."
  exit 0
fi

if [ "$cliff_found" -eq 1 ]; then
  echo "Action: replace the IDs flagged ⛔ before 2026-06-15 — after that date"
  echo "those requests return a hard 404 (not a billing message). The fix is the"
  echo "ID swap shown above; no code logic changes."
else
  echo "Action: replace the flagged IDs with the current ones shown above."
fi
echo
echo "Note: this finds *hardcoded* model strings. It does NOT detect the separate"
echo "2026-06-15 billing change (claude -p / Agent SDK / GitHub Actions move to a"
echo "separate credit pool). For that, see the free guides below."
echo
echo "Free, MIT — Claude Code safety hooks (rm -rf, secret leaks, force-push, more):"
echo "  npx cc-safe-setup"
echo "Free — the 2026-06-15 billing change, plain English (who's affected + 2 actions):"
echo "  https://yurukusa.github.io/cc-safe-setup/claude-code-june-15-billing-change.html"
exit 1
