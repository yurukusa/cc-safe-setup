#!/bin/bash
# Three example guards blocked a destructive command and then passed the same
# command once it was wrapped.
#
# The shapes measured 2026-08-04, against the shipped files:
#
#   rm-safety-net              8 of 10 forms passed
#   system-dir-protection-guard 9 of 11 forms passed
#   auto-mode-safety-enforcer   5 of  9 forms passed
#
# Two separate causes, both about where a command is allowed to start:
#
#   1. The analysis gate. `rm-safety-net` and `system-dir-protection-guard`
#      opened only on '^\s*(sudo\s+)?rm\s' — the command had to *begin* with
#      rm, so `cd /tmp && rm -rf ~` never entered the analysis at all.
#   2. The target pattern. `auto-mode-safety-enforcer` required whitespace or
#      end-of-line after the dangerous path, so `rm -rf ~; echo done` passed
#      while `rm -rf ~ ; echo done` was blocked. One space apart, opposite
#      verdicts.
#
# Wrappers hit both: inside a substitution or after `then`, a command is at
# neither the line start nor a separator. Claude Code 2.1.221 fixed the same
# shape in its own permission check ("hidden commands in [[ ]] regex
# conditionals"), which is what prompted measuring these.
#
# Half of this file is controls. The fix inserts separators at wrapper tokens,
# and parentheses and braces appear in ordinary commands (awk, jq, find -exec,
# subshells), so "looks inside wrappers" and "blocks anything with a bracket"
# have to be told apart. The home-path controls matter too: `ls ~/projects` and
# `cat ~/.bashrc` must stay untouched.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
RM=$(printf 'r%s' 'm')

run() {
  local hook="$1" cmd="$2" T rc
  T="$(mktemp -d)"
  python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},
                  "cwd":sys.argv[2],"session_id":"t"}))' "$cmd" "$T" \
    | HOME="$T" bash "$ROOT/examples/$hook.sh" >/dev/null 2>&1
  rc=$?
  find "$T" -mindepth 1 -delete 2>/dev/null; rmdir "$T" 2>/dev/null
  return $rc
}

want_block() {
  if run "$1" "$2"; then FAIL=$((FAIL+1)); echo "  FAIL blocked [$1]: $2"
  else PASS=$((PASS+1)); echo "  ok   blocked [$1]: $2"; fi
}
want_allow() {
  if run "$1" "$2"; then PASS=$((PASS+1)); echo "  ok   allowed [$1]: $2"
  else FAIL=$((FAIL+1)); echo "  FAIL allowed [$1]: $2"; fi
}

echo "example-guards-wrapped-command"

# --- rm-safety-net -----------------------------------------------------------
H=rm-safety-net
want_block $H "$RM -rf ~"
want_block $H "cd /tmp && $RM -rf ~"
want_block $H "[[ -n \$($RM -rf ~) ]]"
want_block $H "[[ -n \`$RM -rf ~\` ]]"
want_block $H "if true; then $RM -rf ~; fi"
want_block $H "for f in a; do $RM -rf ~; done"
want_block $H "( $RM -rf ~ )"
want_block $H "x=\$($RM -rf /etc)"
want_block $H "npm ci && $RM -rf /home/user"
want_allow $H "$RM -rf node_modules"
want_allow $H "cd app && $RM -rf node_modules && npm ci"
want_allow $H "npm run confirm ~/project"
want_allow $H "echo 'please confirm ~/data first'"
want_allow $H "rmdir empty-dir"
want_allow $H "awk '{print \$1}' access.log"
want_allow $H "( cd /tmp && ls )"
want_allow $H "echo \$(basename \$(pwd))"

# --- system-dir-protection-guard ---------------------------------------------
H=system-dir-protection-guard
want_block $H "$RM -rf /etc"
want_block $H "cd /tmp && $RM -rf /etc"
want_block $H "[[ -n \$($RM -rf /etc) ]]"
want_block $H "if true; then $RM -rf /usr; fi"
want_block $H "for f in a; do $RM -rf /var; done"
want_block $H "( $RM -rf /etc )"
want_block $H "npm ci && mv /etc /tmp/x"
want_block $H "true && chmod -R 777 /etc"
want_allow $H "ls -la /etc"
want_allow $H "cat /etc/hosts"
want_allow $H "mv old.txt new.txt"
want_allow $H "chmod -R 755 ./public"
want_allow $H "awk '{print \$1}' /var/log/app.log"
want_allow $H "( cd /tmp && ls )"
want_allow $H "grep -r 'TODO' /home/me/project"

# --- auto-mode-safety-enforcer -----------------------------------------------
H=auto-mode-safety-enforcer
want_block $H "$RM -rf ~; echo done"
want_block $H "[[ -n \$($RM -rf ~) ]]"
want_block $H "if true; then $RM -rf ~; fi"
want_block $H "for f in a; do $RM -rf ~; done"
want_block $H "x=\$($RM -rf /etc)"
want_allow $H "ls ~/projects"
want_allow $H "cat ~/.bashrc"
want_allow $H "cp -r ~/a ~/b"
want_allow $H "du -sh ~/"
want_allow $H "$RM -rf node_modules"
want_allow $H "jq '{a: .b}' package.json"

# --- bash-project-fence -------------------------------------------------------
# Different concern: this one fences *paths outside the project root*, not
# destructive verbs. Its word split does not break on ( ) or a backtick, so a
# path inside a substitution arrived as the token "~)" — matching neither the
# "~/" case nor the absolute-path case, and the reference passed unnoticed.
# The fix strips the wrapping punctuation from the token edges.
fence_run() {
  local cmd="$1" P rc
  P="$(mktemp -d)"
  mkdir -p "$P/src"
  python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},
                  "cwd":sys.argv[2],"session_id":"t"}))' "$cmd" "$P" \
    | (cd "$P" && CLAUDE_PROJECT_DIR="$P" HOME=/nonexistent-home-for-test \
         bash "$ROOT/examples/bash-project-fence.sh") >/dev/null 2>&1
  # HOME must not sit under /tmp here. /tmp is on this hook's default allow
  # list, and mktemp -d hands out /tmp paths, so a temp HOME makes every `~`
  # case allowed and the four assertions below pass no matter what the code
  # does. The path does not need to exist; only its prefix is compared.
  rc=$?
  find "$P" -mindepth 1 -delete 2>/dev/null; rmdir "$P" 2>/dev/null
  return $rc
}
fence_block() {
  if fence_run "$1"; then FAIL=$((FAIL+1)); echo "  FAIL blocked [fence]: $1"
  else PASS=$((PASS+1)); echo "  ok   blocked [fence]: $1"; fi
}
fence_allow() {
  if fence_run "$1"; then PASS=$((PASS+1)); echo "  ok   allowed [fence]: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL allowed [fence]: $1"; fi
}

fence_block "cat /home/someone/secrets.txt"
fence_block "[[ -n \$(cat /home/someone/secrets.txt) ]]"
fence_block "x=\$(cat /home/someone/secrets.txt)"
fence_block "echo \`cat /home/someone/secrets.txt\`"
# The home directory reached the tokenizer as "~)" and "~`", which match
# neither branch. These are the four that actually failed before the fix; the
# absolute-path forms above were already caught, so they alone would have
# recorded the defect as the spec.
fence_block "[[ -n \$(ls ~) ]]"
fence_block "[[ -n \`ls ~\` ]]"
fence_block "x=\$(ls ~)"
fence_block "( ls ~ )"
fence_allow "ls -la"
fence_allow "git status"
fence_allow "echo hello > /tmp/out.txt"
fence_allow "cat /tmp/scratch"
fence_allow "npm ci && npm run build"
fence_allow "curl -s https://example.com/api"
fence_allow "echo \$(basename \$(pwd))"
fence_allow "for i in \$(seq 1 3); do echo \$i; done"

echo
echo "example-guards-wrapped-command: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
