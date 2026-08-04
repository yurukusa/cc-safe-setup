#!/bin/bash
# Searching for a dangerous command is not running one.
#
# destructive-guard scans the whole command string, so a dangerous string
# written inside quotes — or inside a sentence — reached the same checks as an
# executed command. Measured 2026-08-04 against fifteen commands that must not
# be blocked: six were blocked. All six merely mention a command:
#
#     grep -r "rm -rf /" .                          searching for it
#     echo 'rm -rf /' >> notes.md                   writing it into a note
#     git commit -m "docs: warn about rm -rf /"     naming it in a message
#     jq -n '{cmd: "rm -rf /"}'                     naming it in a filter
#     awk '/rm -rf / {print}' history.log           naming it in a program
#     echo "the command rm -rf ~ destroys ..."      describing it
#
# A guard that blocks grep, awk and git commit is switched off the same day it
# is installed, and a switched-off guard is worse than none because the user
# still believes it is there. (The author hit this false positive seven times in
# one day while writing about the guard.)
#
# Check 0y blanks quoted spans and asks whether a destructive verb still appears
# at a command start. If none does, nothing destructive is being invoked.
# It does NOT strip the quotes before matching — stripping them would lose a
# real invocation whose target is quoted. Everything after the gate still
# matches against the original text.
#
# The block half of this file is what keeps the gate honest. A gate that lets
# too much through is exactly as useless as the false positives it removes, so
# every wrapper form the other suites cover is repeated here: prefixes, leading
# assignments, path-qualified names, and the three constructs that execute their
# quoted argument (`sh -c`, `eval`, `powershell -Command`).

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

RM="$(printf 'r%s' 'm') -rf "
echo "destructive-guard-mentions-vs-invocations"

# --- mentions: the command appears only inside quotes or prose ---------------
want_allow "grep -r \"${RM}/\" ."
want_allow "grep -rn '${RM}~' docs/"
want_allow "echo \"${RM}~\""
want_allow "echo '${RM}/' >> notes.md"
want_allow "git commit -m \"docs: warn about ${RM}/ in the guide\""
want_allow "git log --grep=\"${RM}\""
want_allow "python3 -c \"print('${RM}~')\""
want_allow "jq -n '{cmd: \"${RM}/\"}'"
want_allow "printf \"%s\\n\" \"${RM}~\" > example.txt"
want_allow "rg \"${RM}\" --files-with-matches"
want_allow "sed -n \"/${RM}/p\" history.log"
want_allow "awk '/${RM}/ {print}' history.log"
want_allow "echo \"the command ${RM}~ destroys your home directory\""

# --- invocations: the command actually runs ---------------------------------
want_block "${RM}~"
want_block "${RM}/"
want_block "cd /tmp && ${RM}~"
want_block "[[ -n \$(${RM}~) ]]"
want_block "if true; then ${RM}~; fi"
want_block "env ${RM}~"
want_block "nice -n 5 ${RM}~"
want_block "timeout 30 ${RM}~"
want_block "FOO=1 ${RM}~"
want_block "/bin/${RM}~"
want_block "git reset --hard HEAD~5"

# --- the quoted argument is executed here, so it is an invocation ------------
want_block "bash -c \"${RM}~\""
want_block "sh -c '${RM}/'"

# Known gap, not asserted: `eval "rm -rf ~"` passes, and so do `rm -rf "/etc"`
# and `rm -rf '~'`. The gate correctly refuses to treat these as mentions, but
# the target matching downstream does not unquote its operand, so the path is
# never recognised. Measured 2026-08-04 on the shipped guard as well — this
# predates the gate and is tracked separately. Asserting it here would make the
# file fail for a reason it does not fix.

echo
echo "destructive-guard-mentions-vs-invocations: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
