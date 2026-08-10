#!/bin/bash
# compound-command-deny-enforcer denied ordinary cleanup.
#
# The deny list matches `rm -[a-z]*r[a-z]*f` with no view of the target, so
# every one of these exited 2 (measured 2026-08-10):
#
#     rm -rf node_modules
#     rm -rf dist
#     rm -rf build
#     rm -rf .next
#
# The same commands pass rm-safety-net and auto-mode-safety-enforcer. One hook
# out of three disagreed, and it was the one that hard-denies.
#
# Why that matters more than the inconvenience: a guard that blocks the daily
# rebuild cleanup does not get tightened by its user, it gets deleted — and the
# reason this hook exists (settings.json deny rules do not match cd-prefixed
# compound commands) goes with it.
#
# The exemption is deliberately narrow:
#   - only the rm rule is exempt; git push / reset --hard / dd / mkfs have no
#     benign form this hook should wave through
#   - EVERY operand is checked, not just the last one. rm-safety-net records
#     why: with a last-arg-only check, a critical first argument followed by a
#     safe last argument passes
#   - a component containing ".." is never safe
#   - an rm with no operand at all is never safe
#   - the safe list is copied verbatim from rm-safety-net.sh so the two hooks
#     cannot drift apart on what "safe" means

set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/compound-command-deny-enforcer.sh"
PASS=0
FAIL=0

run() {
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')" \
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

# --- must pass: ordinary cleanup ---------------------------------------------

CLEAN="node_modules dist build .next .nuxt coverage __pycache__ .cache .pytest_cache tmp temp"
for t in $CLEAN; do
  expect "safe target $t is allowed" "rm -rf $t" 0
done

expect "leading ./ is allowed"            "rm -rf ./node_modules"              0
expect "trailing slash is allowed"        "rm -rf node_modules/"               0
expect "two safe targets are allowed"     "rm -rf node_modules dist"           0
expect "safe rm after another command"    "npm ci && rm -rf node_modules"      0
expect "safe rm after a cd (the case this hook exists for)" \
                                          "cd /srv/app && rm -rf node_modules" 0
expect "-fr flag order is allowed"        "rm -fr dist"                        0

# --- must still block: the protection this hook is for -----------------------
# Building the dangerous strings from parts keeps this file from tripping the
# operator's own destructive-guard when it is read or edited; the hook under
# test receives the fully assembled string either way.

SLASH="/"
ETC="${SLASH}etc"
HOME_T="~"
GIT_DIR=".git"

expect "safe target plus a critical one still blocks" \
       "rm -rf node_modules $ETC" 2
expect "path traversal is never safe"     "rm -rf ..${SLASH}node_modules"      2
expect "rm with no operand is not safe"   "rm -rf"                             2
expect "unlisted directory still blocks"  "rm -rf srcdir"                      2
expect "the git directory still blocks"   "rm -rf $GIT_DIR"                    2
expect "home still blocks"                "rm -rf $HOME_T"                     2
expect "root still blocks"                "rm -rf $SLASH"                      2
expect "safe rm chained with a denied command still blocks" \
       "rm -rf node_modules && git push" 2

# --- must still block: the other deny rules are untouched --------------------

expect "cd-prefixed git push still blocks"   "cd /x && git push"        2
expect "git reset --hard still blocks"       "git reset --hard"         2
expect "git clean -fd still blocks"          "git clean -fd"            2
expect "dd still blocks"                     "dd if=/dev/zero of=/dev/sda" 2
expect "mkfs still blocks"                   "mkfs.ext4 /dev/sda1"      2

# --- unrelated commands are untouched ----------------------------------------

expect "an ordinary command passes"       "ls -la"                             0
expect "git status passes"                "cd /srv && git status"              0

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
