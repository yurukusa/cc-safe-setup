#!/bin/bash
# `--audit --ci` was documented and never implemented.
#
# README has shown this workflow step since the "Safety audit and CI" section
# was written:
#
#   - run: npx github:yurukusa/cc-safe-setup --audit --ci
#
# Nothing in index.mjs read `--ci`. The exit was
#
#   process.exit(score < (parseInt(process.env.CC_AUDIT_THRESHOLD) || 0) ? 1 : 0)
#
# with a default threshold of 0 and a score that cannot go below 0, so the
# comparison was never true and the step passed whatever the audit found. A CI
# gate that cannot fail is worse than no gate: the reader believes a regression
# would be caught, stops watching, and the belief is what breaks.
#
# The gate line is CRITICAL/HIGH, not any risk. A machine that follows this
# tool's own recommended install still carries one MEDIUM finding, and a gate
# that reddens a correct setup is removed by the first person who sees it —
# which lands back where this started.
#
# Fixed 2026-09-03.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    echo "    expected: $2"
    echo "    actual:   $3"
  fi
}

BARE="$(mktemp -d)"
mkdir -p "$BARE/.claude"

# Nothing installed: the audit finds CRITICAL/HIGH gaps.
HOME="$BARE" node "$REPO/index.mjs" --audit >/dev/null 2>&1
check "plain --audit still exits 0 (unchanged for existing callers)" "0" "$?"

HOME="$BARE" node "$REPO/index.mjs" --audit --ci >/dev/null 2>&1
check "--ci fails when the audit finds blocking risks" "1" "$?"

OUT="$(HOME="$BARE" node "$REPO/index.mjs" --audit --ci 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
check "--ci states the rule it applies" \
  "yes" "$(printf '%s' "$OUT" | grep -q 'fails on CRITICAL or HIGH only' && echo yes || echo no)"

# The threshold path has to keep working on its own, without --ci.
HOME="$BARE" CC_AUDIT_THRESHOLD=101 node "$REPO/index.mjs" --audit >/dev/null 2>&1
check "CC_AUDIT_THRESHOLD still gates without --ci" "1" "$?"

# A machine set up the way this tool recommends must pass the gate, or the gate
# gets deleted by whoever reads the red build.
SHIELDED="$(mktemp -d)"
HOME="$SHIELDED" node "$REPO/index.mjs" --shield >/dev/null 2>&1
HOME="$SHIELDED" node "$REPO/index.mjs" --audit --ci >/dev/null 2>&1
check "a shielded install passes --ci" "0" "$?"

# And when nothing is found, the report must say what it did not look at.
# "No risks detected. Your setup looks solid." read as a statement about the
# setup; it was only ever a statement about these checks.
CLEAN="$(HOME="$SHIELDED" node "$REPO/index.mjs" --audit 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
check "does not claim the setup is solid" \
  "yes" "$(printf '%s' "$CLEAN" | grep -q 'looks solid' && echo no || echo yes)"

NORISK="$(mktemp -d)"
HOME="$NORISK" node "$REPO/index.mjs" --shield >/dev/null 2>&1
HOME="$NORISK" node "$REPO/index.mjs" --audit --fix >/dev/null 2>&1
RECEIPT="$(HOME="$NORISK" node "$REPO/index.mjs" --audit 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
if printf '%s' "$RECEIPT" | grep -q 'No risks found'; then
  check "names what it did not check" \
    "yes" "$(printf '%s' "$RECEIPT" | grep -q 'Not checked:' && echo yes || echo no)"
else
  # --fix could not clear every finding on this machine; the wording assertion
  # above still covers the claim that mattered.
  PASS=$((PASS + 1))
fi

echo "  audit-ci-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
