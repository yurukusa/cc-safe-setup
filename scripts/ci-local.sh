#!/bin/bash
# ================================================================
# ci-local.sh — run the cheap half of CI before you commit
# ================================================================
# WHY THIS EXISTS
#   `npm test` runs `bash test.sh` and nothing else, but
#   .github/workflows/test.yml stacks four more checks on top of it. Over the
#   fortnight to 2026-08-10, 25 of 311 Tests runs went red and 17 of those 25
#   were the same line: "docs/search-index.json is out of date". Not one of
#   them could have been caught locally, because no command existed that ran
#   what CI runs. Every red one mailed the repository owner.
#
#   So this script is the missing command. It mirrors the four steps of
#   test.yml that cost about a second in total, in the same order, with the
#   same pass/fail conditions:
#
#     1. CLI smoke tests            node index.mjs --help / --dry-run
#     2. Example hooks syntax check bash -n over examples/*.sh
#     3. Hook TRIGGER headers       scripts/check-hook-event-names.py
#     4. Generated search index     build-search-index.py + git diff
#
#   Step 4 regenerates docs/search-index.json in place, so when it fails the
#   fix is already sitting in your working tree: `git add docs/search-index.json`
#   and commit. Better still, point git at the tracked hooks directory once and
#   it happens by itself:
#
#     git config core.hooksPath scripts/hooks
#
# WHAT THIS DOES NOT COVER
#   The two expensive steps stay in CI: `bash test.sh` (the main suite) and the
#   per-hook suites under tests/. Run `bash test.sh` yourself before anything
#   that touches hook behaviour — this script is the pre-commit floor, not a
#   replacement for it.
#
# Usage:  bash scripts/ci-local.sh        (exit 0 = the four checks pass)
# ================================================================
set -u

cd "$(dirname "$0")/.." || exit 1

FAILED=""
STEP=0

# Every step runs even after one fails. A single pass that lists all four
# verdicts beats four edit-run cycles, and none of these steps can corrupt the
# next one.
start() {
    STEP=$((STEP + 1))
    printf '\n=== [%d/4] %s ===\n' "$STEP" "$1"
}

fail() {
    FAILED="$FAILED
  - $1"
}

# --- 1. CLI smoke tests ---------------------------------------------------
start "CLI smoke tests"
if node index.mjs --help >/dev/null && node index.mjs --dry-run >/dev/null; then
    echo "index.mjs --help and --dry-run both exited 0"
else
    echo "index.mjs --help or --dry-run failed (rerun without >/dev/null to see it)"
    fail "CLI smoke tests"
fi

# --- 2. Example hooks syntax check ---------------------------------------
# Unlike CI this leaves bash's own error text on screen; the verdict is the
# same, but locally you want the line number, not just the filename.
start "Example hooks syntax check"
ERRORS=0
TOTAL=0
for f in examples/*.sh; do
    TOTAL=$((TOTAL + 1))
    if ! bash -n "$f"; then
        echo "SYNTAX ERROR: $f"
        ERRORS=$((ERRORS + 1))
    fi
done
echo "$((TOTAL - ERRORS))/$TOTAL examples passed syntax check"
[ "$ERRORS" -eq 0 ] || fail "Example hooks syntax check ($ERRORS file(s))"

# --- 3. Hook TRIGGER headers name real events ----------------------------
start "Hook TRIGGER headers name real events"
python3 scripts/check-hook-event-names.py || fail "Hook TRIGGER headers"

# --- 4. Generated search index is current --------------------------------
start "Generated search index is current"
if ! python3 scripts/build-search-index.py; then
    fail "build-search-index.py did not run"
elif ! git diff --quiet -- docs/search-index.json; then
    echo "docs/search-index.json is out of date."
    git diff --stat -- docs/search-index.json
    echo "It has just been regenerated for you. Stage it with:"
    echo "    git add docs/search-index.json"
    fail "Generated search index is out of date"
else
    echo "docs/search-index.json matches docs/*.html"
fi

# --- verdict --------------------------------------------------------------
echo
if [ -z "$FAILED" ]; then
    echo "OK: the four cheap CI steps pass. (bash test.sh and tests/ still run in CI.)"
    exit 0
fi
echo "FAILED:$FAILED"
echo
echo "CI runs these same four steps, so pushing now sends the owner a failure mail."
exit 1
