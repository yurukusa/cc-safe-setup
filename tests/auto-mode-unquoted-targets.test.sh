#!/bin/bash
# auto-mode-safety-enforcer promised more than it blocked.
#
# The header of that hook says it blocks:
#
#     rm -rf on non-safe paths (/, ~, .., /home, /etc, /usr, /var, .git)
#
# Measured 2026-08-11 against 19 targets it claims: 11 were not blocked.
# The target pattern only ends on whitespace, a separator or end-of-line, and
# it has no case for $HOME, for a parent traversal, or for the git directory:
#
#     rm -rf $HOME        passed        rm -rf ..                 passed
#     rm -rf ${HOME}      passed        rm -rf ../..              passed
#     rm -rf .git         passed        rm -rf a/../..            passed
#
# Same defect family as PR #961 (quoted target) and #962 (variable target),
# which fixed scripts.json only. The example hook never received either fix.
#
# --- deliberately NOT fixed here ---------------------------------------------
# Five of the eleven need the target seen through quotes:
#
#     rm -rf "/"   rm -rf '/'   rm -rf "$HOME"   rm -rf "${HOME}"   rm -rf ".git"
#
# Adding a quote to the terminator set would also block these, which are
# mentions and must keep passing:
#
#     echo "rm -rf /"        git commit -m "guard against rm -rf /"
#
# Both shapes end in /" and this hook has no mention-vs-invocation pass — the
# five above pass today only because the target is invisible behind the quote,
# not because the hook can tell a mention from a run. Telling them apart needs
# the quote-aware extraction destructive-guard grew in PR #960. Until that is
# ported, the mention controls at the bottom of this file are the guarantee
# that no such false positive was introduced.

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

# Dangerous strings are assembled from parts so that reading or editing this
# file does not trip the operator's own destructive-guard. The hook under test
# receives the fully assembled string either way.
SLASH="/"
DOTDOT="..${SLASH}"
GIT_DIR=".git"
HOME_VAR='$HOME'
HOME_BRACED='${HOME}'

# --- the gap this file closes ------------------------------------------------

expect "home through the variable"        "rm -rf $HOME_VAR"                  2
expect "home through the braced variable" "rm -rf $HOME_BRACED"               2
expect "home variable with a subpath"     "rm -rf $HOME_VAR${SLASH}projects"  2
expect "bare parent traversal"            "rm -rf .."                         2
expect "repeated parent traversal"        "rm -rf $DOTDOT.."                  2
expect "traversal hidden after a safe name" \
                                          "rm -rf node_modules${SLASH}$DOTDOT.." 2
expect "the git directory"                "rm -rf $GIT_DIR"                   2
expect "the git directory with a slash"   "rm -rf $GIT_DIR$SLASH"             2

# --- what already worked must keep working -----------------------------------

expect "root still blocks"                "rm -rf $SLASH"                     2
expect "home tilde still blocks"          "rm -rf ~"                          2
expect "etc still blocks"                 "rm -rf ${SLASH}etc"                2
expect "usr still blocks"                 "rm -rf ${SLASH}usr"                2
expect "ssh directory still blocks"       "rm -rf ~${SLASH}.ssh"              2

# --- ordinary cleanup must not be caught -------------------------------------

expect "node_modules is allowed"          "rm -rf node_modules"               0
expect "dist is allowed"                  "rm -rf dist"                       0
expect "leading ./ is allowed"            "rm -rf .${SLASH}build"             0
expect "cleanup after another command"    "npm ci && rm -rf node_modules"     0
expect "an unlisted directory is allowed" "rm -rf tmpdir"                     0
expect "gitignore is not the git directory" \
                                          "rm -rf .gitignore"                 0
expect "the github directory is not the git directory" \
                                          "rm -rf .github"                    0
expect "a dotted name is not a traversal" "rm -rf my..cache"                  0
expect "a file ending in two dots is not a traversal" \
                                          "rm -rf backup.."                   0

# --- mentions must keep passing (the reason quotes are left alone) -----------

expect "a mention in echo is not a run"   "echo \"rm -rf $SLASH\""            0
expect "a mention in a commit message is not a run" \
                                          "git commit -m \"guard against rm -rf $SLASH\"" 0
expect "a mention in grep is not a run"   "grep -r \"rm -rf $SLASH\" ."       0

echo "auto-mode-unquoted-targets: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
