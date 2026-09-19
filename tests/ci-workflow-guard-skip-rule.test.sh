#!/bin/bash
# ci-workflow-guard: does the "test/verification skip" rule actually fire?
#
# Why this exists. The four existing checks for this hook in test.sh pass file
# paths that do not exist and only assert exit 0. This hook always exits 0, so
# they pass whether any rule fires or not - the same shape as the "234 test
# files that could not fail" noted in the CI workflow.
#
# The regression being pinned: the skip rule was written as
#   grep -qE '--no-verify|--skip-tests|--no-check|SKIP_CI|skip ci|\[ci skip\]'
# without `--`, so grep read the leading dashes of --no-verify as options,
# died with "invalid option" and never matched anything. The whole rule was
# dead.
#
# It was masked. A separate rule on the next lines matches
# 'dangerously-skip-permissions|--force|--no-verify' and starts with a letter,
# so it works - and it also contains --no-verify. Anyone spot-checking with
# --no-verify saw a warning and moved on. The terms only this rule covers
# (SKIP_CI, skip ci, [ci skip], --skip-tests, --no-check) produced nothing at
# all. Measured 2026-09-20.
#
# Both directions are asserted: a guard that also fires on an ordinary
# workflow is a guard operators learn to ignore.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/examples/ci-workflow-guard.sh"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.github/workflows"

fires() { # fires <name> <workflow-body> <expected-substring|NONE>
  local wf="$TMP/.github/workflows/w.yml"
  printf '%s\n' "$2" > "$wf"
  local err
  err=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$wf" \
        | bash "$HOOK" 2>&1 >/dev/null)
  if [ "$3" = "NONE" ]; then
    if [ -z "$err" ]; then PASS=$((PASS + 1)); return; fi
    FAIL=$((FAIL + 1)); echo "  FAIL: $1 (expected silence)"; echo "        stderr: $err"; return
  fi
  case "$err" in
    *"$3"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "  FAIL: $1 (expected '$3')"; echo "        stderr: $err" ;;
  esac
}

echo "ci-workflow-guard-skip-rule:"

# --- terms only the skip rule covers: these are the ones that were dead -----
fires "SKIP_CI env"      "env:
  SKIP_CI: true"                              "Test/verification skip detected"
fires "skip ci in a message" "jobs:
  b:
    steps:
      - run: git commit -m 'skip ci'"        "Test/verification skip detected"
fires "[ci skip] in a message" "jobs:
  b:
    steps:
      - run: git commit -m '[ci skip] wip'"  "Test/verification skip detected"
fires "--skip-tests flag" "jobs:
  b:
    steps:
      - run: make build --skip-tests"        "Test/verification skip detected"
fires "--no-check flag" "jobs:
  b:
    steps:
      - run: deploy --no-check"              "Test/verification skip detected"

# --- the term that was masked by the neighbouring rule ----------------------
fires "--no-verify still flagged by the skip rule" "jobs:
  b:
    steps:
      - run: git commit --no-verify"         "Test/verification skip detected"

# --- an ordinary workflow must stay silent ---------------------------------
fires "ordinary workflow is quiet" "name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test"                        NONE

# --- no rule may make grep error out ---------------------------------------
wf="$TMP/.github/workflows/w.yml"
printf 'name: ci\non: push\n' > "$wf"
err=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$wf" \
      | bash "$HOOK" 2>&1 >/dev/null)
case "$err" in
  *"invalid option"*|*"unrecognized option"*|*"Usage: grep"*)
    FAIL=$((FAIL + 1))
    echo "  FAIL: a pattern is malformed and grep is erroring out"
    echo "        stderr: $err" ;;
  *) PASS=$((PASS + 1)) ;;
esac

# --- the hook reports; it must not interrupt -------------------------------
printf '%s\n' "env:
  SKIP_CI: true" > "$wf"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$wf" \
  | bash "$HOOK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: hook must not interrupt (expected exit 0, got $rc)"
fi

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
