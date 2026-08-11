#!/bin/bash
# The five quoted targets auto-mode-safety-enforcer left alone, and the mentions
# that had to keep passing.
#
# PR #1008 closed eleven of nineteen gaps in that hook but stopped at the quoted
# forms, and said why in the file itself:
#
#     Quoted forms ("/", "$HOME", ".git") are deliberately still not matched.
#     This hook has no mention-vs-invocation pass, so putting a quote in a
#     terminator set would also block `echo "rm -rf /"` and a commit message
#     that names the command.
#
# That is now ported: the hook blanks out everything inside quotes and asks
# whether a destructive verb still starts a command in what is left. If none
# does, it exits 0 before any pattern runs. With mentions ruled out, quote
# characters can be dropped from the text the patterns match against, so a
# quoted target is judged like a bare one.
#
# Two halves, and both are the point:
#   - the quoted targets must now be blocked   (this closes the remaining five)
#   - the mentions must still pass             (this proves nothing was widened)
#
# Against the version before this change, the first half fails: the quoted
# targets were invisible, so every one of them exited 0.
#
# Dangerous strings are assembled from parts so that reading or editing this
# file does not trip the operator's own destructive-guard. The hook under test
# receives the fully assembled string either way.

set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/auto-mode-safety-enforcer.sh"
PASS=0
FAIL=0

run() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

expect() { # description command expected_exit
  actual="$(run "$2")"
  if [ "$actual" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    echo "        command:  $2"
    echo "        expected: exit $3, got exit $actual"
  fi
}

RM="r""m -rf"
SLASH="/"
GIT_DIR=".git"
HOME_VAR='$HOME'
HOME_BRACED='${HOME}'
DQ='"'
SQ="'"

# --- the five that were left alone -------------------------------------------

expect "a double-quoted root is a run" \
  "$RM ${DQ}${SLASH}${DQ}"                                        2
expect "a single-quoted root is a run" \
  "$RM ${SQ}${SLASH}${SQ}"                                        2
expect "a quoted home variable is a run" \
  "$RM ${DQ}${HOME_VAR}${DQ}"                                     2
expect "a quoted braced home variable is a run" \
  "$RM ${DQ}${HOME_BRACED}${DQ}"                                  2
expect "a quoted git directory is a run" \
  "$RM ${DQ}${GIT_DIR}${DQ}"                                      2

# --- other quoted targets the header claims ----------------------------------

expect "a quoted tilde is a run"        "$RM ${DQ}~${DQ}"         2
expect "a quoted etc is a run"          "$RM ${DQ}${SLASH}etc${DQ}" 2
expect "a quoted parent traversal is a run" \
  "$RM ${DQ}..${DQ}"                                              2
expect "a quoted target after another command is a run" \
  "npm ci && $RM ${DQ}${SLASH}${DQ}"                              2

# --- mentions must still pass (nothing was widened) --------------------------

expect "a mention in echo is not a run" \
  "echo ${DQ}${RM} ${SLASH}${DQ}"                                 0
expect "a mention in a commit message is not a run" \
  "git commit -m ${DQ}guard against ${RM} ${SLASH}${DQ}"          0
expect "a mention in grep is not a run" \
  "grep -r ${DQ}${RM} ${SLASH}${DQ} ."                            0
expect "a mention in a jq filter is not a run" \
  "jq -n ${SQ}{cmd: ${DQ}${RM} ${SLASH}${DQ}}${SQ}"               0
expect "a mention in prose is not a run" \
  "echo ${DQ}the command ${RM} ${SLASH} destroys everything${DQ}" 0
expect "a mention of the home variable is not a run" \
  "echo ${DQ}never write ${RM} ${HOME_VAR}${DQ}"                  0
expect "appending a mention to a note is not a run" \
  "echo ${SQ}${RM} ${SLASH} is the one to avoid${SQ} >> notes.md"  0

# --- quoted safe targets must pass -------------------------------------------
# This is the false-positive half. Dropping quote characters must not turn an
# ordinary quoted cleanup into a block.

expect "a quoted node_modules is allowed" \
  "$RM ${DQ}node_modules${DQ}"                                    0
expect "a quoted dist is allowed"       "$RM ${DQ}dist${DQ}"      0
expect "a quoted name with a space is allowed" \
  "$RM ${DQ}my build dir${DQ}"                                    0
expect "a quoted gitignore is not the git directory" \
  "$RM ${DQ}.gitignore${DQ}"                                      0

# --- quoted text that is executed is not a mention ---------------------------
# A quoted string is only inert while nothing runs it. These do run it, so the
# gate must not let them through on the grounds that the verb sits in quotes.

expect "sh -c runs its quoted argument" \
  "sh -c ${DQ}${RM} ${SLASH}${DQ}"                                2
expect "bash -c runs its quoted argument" \
  "bash -c ${SQ}${RM} ~${SQ}"                                     2
expect "eval runs its quoted argument" \
  "eval ${DQ}${RM} ${SLASH}${DQ}"                                 2
expect "a pipe into a shell runs what was piped" \
  "echo ${DQ}${RM} ${SLASH}${DQ} | sh"                            2

echo "auto-mode-quoted-targets: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
