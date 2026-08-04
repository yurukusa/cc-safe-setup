#!/bin/bash
# destructive-guard never looked inside a wrapper.
#
# Every boundary in the guard is (^|[;&|]) — the start of the line, or just
# after a separator. A command placed inside a substitution, a subshell, or
# after a shell keyword sits at neither, so no check ever saw it:
#
#     rm -rf ~                    blocked
#     [[ -n $(rm -rf ~) ]]        NOT blocked   <- same deletion
#     if true; then rm -rf ~; fi  NOT blocked
#     `rm -rf ~`                  NOT blocked
#
# Measured 2026-08-04 against the shipped core: one blocked command, ten
# wrappings, seven passes. Claude Code 2.1.221 fixed the same shape on its own
# side ("a Bash tool permission-check bypass where zsh could execute hidden
# commands in [[ ]] regex conditionals"), which is what prompted the check here.
#
# Check 0z replaces the wrapping tokens with separators and runs the guard once
# more against that text, so the inner command meets every existing check. The
# controls below are the point of this file: the rewrite touches parentheses and
# braces, which appear in ordinary commands (awk, jq, find -exec, subshells), so
# "catches wrapped commands" and "blocks anything with a bracket in it" have to
# be told apart.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'find "$WORK" -mindepth 1 -delete 2>/dev/null; rmdir "$WORK" 2>/dev/null' EXIT
PASS=0; FAIL=0

python3 -c "
import json,sys
sys.stdout.write(json.load(open('$ROOT/scripts.json'))['destructive-guard'])" > "$WORK/dg.sh"

run() {
  local T; T="$(mktemp -d)"
  python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},
                  "cwd":sys.argv[2],"session_id":"t"}))' "$1" "$T" \
    | HOME="$T" bash "$WORK/dg.sh" >/dev/null 2>&1
  local rc=$?
  find "$T" -mindepth 1 -delete 2>/dev/null; rmdir "$T" 2>/dev/null
  return $rc
}

want_block() {
  if run "$1"; then FAIL=$((FAIL+1)); echo "  FAIL blocked: $1"
  else PASS=$((PASS+1)); echo "  ok   blocked: $1"; fi
}
want_allow() {
  if run "$1"; then PASS=$((PASS+1)); echo "  ok   allowed: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL allowed: $1"; fi
}

RM=$(printf 'r%s' 'm')
echo "destructive-guard-wrapped-command"

# --- the same deletion, wrapped ---------------------------------------------
want_block "[[ -n \$($RM -rf ~) ]]"
want_block "[[ x =~ \$($RM -rf ~) ]]"
want_block "[[ -n \`$RM -rf ~\` ]]"
want_block "if true; then $RM -rf ~; fi"
want_block "for f in a; do $RM -rf ~; done"
want_block "\$($RM -rf /)"
want_block "x=\$($RM -rf /) ; echo done"
want_block "echo \$(git reset --hard HEAD~5)"

# --- unwrapped, which already worked ----------------------------------------
want_block "$RM -rf ~"
want_block "$RM -rf /"

# --- controls: brackets and braces are ordinary ------------------------------
# Without these, the check above passes just as well by blocking every command
# that contains a parenthesis.
want_allow "awk '{print \$1}' access.log"
want_allow "sed -E 's/(a)/b/' file.txt"
want_allow "jq '{name: .name}' package.json"
want_allow "find . -name '*.log' -exec ls -l {} \\;"
want_allow "if [ -d node_modules ]; then echo yes; else echo no; fi"
want_allow "for i in \$(seq 1 3); do echo \$i; done"
want_allow "echo \$(basename \$(pwd))"
want_allow "( cd /tmp && ls )"
want_allow "ls \$(git rev-parse --show-toplevel)"
want_allow "$RM -rf node_modules && npm ci"
want_allow "git reset --soft HEAD~1"
want_allow "bash -c 'echo hello'"

echo
echo "destructive-guard-wrapped-command: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
