#!/bin/bash
# The two guards that still judged a target by its quotes, and the mention that
# one of them blocked.
#
# Measured 2026-08-11 (before this change), same eight inputs through three hooks:
#
#                                     auto-mode  rm-safety-net  compound-deny
#   a quoted safe target                 ok         BLOCKED        BLOCKED
#   a quoted safe target (single)        ok         BLOCKED        BLOCKED
#   a quoted safe target (dist)          ok         BLOCKED        BLOCKED
#   a mention in echo                    ok         ok             BLOCKED
#
# auto-mode-safety-enforcer had just been fixed (PR #1009). The other two had
# not, and they fail for two different reasons:
#
#   rm-safety-net blocks anything that is not on its safe list, so a quote made
#   an ordinary cleanup fail the same test a dangerous path fails -- the quote,
#   not the path, decided it.
#
#   compound-command-deny-enforcer compares each operand against the safe list
#   as a literal name, so a quoted name never matched, and the deny patterns
#   then saw the whole line. It also had no mention-vs-invocation pass at all,
#   which is why naming a command inside echo was blocked.
#
# Both now drop quote characters before judging a target, and the compound guard
# received the same gate auto-mode got in PR #1009.
#
# --- known limit, asserted on purpose ----------------------------------------
# A name containing spaces is still blocked by both. That is word splitting, not
# quoting: the operands are cut apart on whitespace, so a quoted name with a
# space in it arrives as several words. Fixing it means rewriting how operands
# are extracted. The cases at the bottom record the current behaviour so that a
# future change to that code shows up here instead of passing unnoticed.
#
# Dangerous strings are assembled from parts so that reading or editing this
# file does not trip the operator's own destructive-guard.

set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)/examples"
PASS=0
FAIL=0

run() { # hook command
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
    | bash "$DIR/$1.sh" >/dev/null 2>&1
  echo $?
}

expect() { # hook description command expected_exit
  actual="$(run "$1" "$3")"
  if [ "$actual" = "$4" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL [$1]: $2"
    echo "        command:  $3"
    echo "        expected: exit $4, got exit $actual"
  fi
}

RM="r""m -rf"
SLASH="/"
DQ='"'
SQ="'"
HOME_VAR='$HOME'

for h in rm-safety-net compound-command-deny-enforcer auto-mode-safety-enforcer; do

  # --- quoted safe targets must pass ----------------------------------------

  expect "$h" "a quoted safe target is ordinary cleanup" \
    "$RM ${DQ}node_modules${DQ}"                                  0
  expect "$h" "a single-quoted safe target is ordinary cleanup" \
    "$RM ${SQ}node_modules${SQ}"                                  0
  expect "$h" "a quoted dist is ordinary cleanup" \
    "$RM ${DQ}dist${DQ}"                                          0
  expect "$h" "a quoted build is ordinary cleanup" \
    "$RM ${DQ}build${DQ}"                                         0
  expect "$h" "a bare safe target still passes" \
    "$RM node_modules"                                            0
  expect "$h" "cleanup after another command still passes" \
    "npm ci && $RM ${DQ}node_modules${DQ}"                        0

  # --- mentions must pass ----------------------------------------------------

  expect "$h" "a mention in echo is not a run" \
    "echo ${DQ}${RM} ${SLASH}${DQ}"                               0
  expect "$h" "a mention in a commit message is not a run" \
    "git commit -m ${DQ}guard against ${RM} ${SLASH}${DQ}"        0
  expect "$h" "a mention of the home variable is not a run" \
    "echo ${DQ}never write ${RM} ${HOME_VAR}${DQ}"                0

  # --- quoted dangerous targets must still be blocked -----------------------

  expect "$h" "a quoted root is a run" \
    "$RM ${DQ}${SLASH}${DQ}"                                      2
  expect "$h" "a quoted home variable is a run" \
    "$RM ${DQ}${HOME_VAR}${DQ}"                                   2
  expect "$h" "a quoted etc is a run" \
    "$RM ${DQ}${SLASH}etc${DQ}"                                   2

  # --- quoted text that is executed is not a mention ------------------------
  # Only the two guards that carry the gate judge this. rm-safety-net looks at
  # the target of an rm and has no unwrapping step, so a deletion handed to a
  # shell has always passed it (measured on the version before this change too
  # -- not a regression introduced here). destructive-guard is the layer that
  # catches it, and the bottom of this file checks that it does.
  case "$h" in
    rm-safety-net) WRAP_EXEC=0 ;;
    *)             WRAP_EXEC=2 ;;
  esac
  expect "$h" "sh -c runs its quoted argument" \
    "sh -c ${DQ}${RM} ${SLASH}${DQ}"                              "$WRAP_EXEC"
  expect "$h" "eval runs its quoted argument" \
    "eval ${DQ}${RM} ${SLASH}${DQ}"                               "$WRAP_EXEC"

  # --- known limit: a name with spaces --------------------------------------
  # Word splitting, not quoting: the operands are cut apart on whitespace, so a
  # quoted name containing a space arrives as several words. The two safe-list
  # guards block it (the words are not on the list). auto-mode works off a list
  # of dangerous paths instead, so an unlisted name passes there. Both are the
  # behaviour before this change; the assertions are here so that a future
  # rewrite of operand extraction shows up in this file.
  case "$h" in
    auto-mode-safety-enforcer) SPACED=0 ;;
    *)                         SPACED=2 ;;
  esac
  expect "$h" "KNOWN LIMIT: a quoted name with a space" \
    "$RM ${DQ}my build dir${DQ}"                                  "$SPACED"

done

# --- the layer that catches what rm-safety-net does not ----------------------
# rm-safety-net passes a deletion handed to a shell (it has no unwrapping step),
# so the claim "another layer catches it" has to be checked, not asserted.
# destructive-guard lives in scripts.json, so it is extracted the same way
# tests/destructive-guard-mentions-vs-invocations.test.sh extracts it.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
python3 -c "import json,sys;
sys.stdout.write(json.load(open('$ROOT/scripts.json'))['destructive-guard'])" > "$WORK/dg.sh"

run_dg() { # command
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/\"/\\\"/g; s/^/\"/; s/$/\"/')" \
    | bash "$WORK/dg.sh" >/dev/null 2>&1
  echo $?
}

expect_dg() { # description command expected_exit
  actual="$(run_dg "$2")"
  if [ "$actual" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL [destructive-guard]: $1"
    echo "        command:  $2"
    echo "        expected: exit $3, got exit $actual"
  fi
}

expect_dg "sh -c with a quoted deletion is caught by the core guard" \
  "sh -c ${DQ}${RM} ${SLASH}${DQ}"                                2
expect_dg "eval with a quoted deletion is caught by the core guard" \
  "eval ${DQ}${RM} ${SLASH}${DQ}"                                 2
expect_dg "a mention stays a mention in the core guard too" \
  "echo ${DQ}${RM} ${SLASH}${DQ}"                                 0

rm -rf "$WORK" 2>/dev/null

echo "quoted-safe-targets-and-mentions: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
