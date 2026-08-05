#!/bin/bash
# Putting the target in a variable made the deletion invisible.
#
# Every check keys on the literal text of the command, so a path held in a
# variable was never seen:
#
#     rm -rf /etc              blocked
#     D=/etc; rm -rf $D        NOT blocked   <- same deletion, same command string
#     CMD="rm -rf /"; $CMD     NOT blocked
#
# Assigning a path to a variable is ordinary shell, not an evasion technique —
# the same shape as the quoted-target hole (#961): the more carefully someone
# writes the script, the less protected they were. Measured 2026-08-06 against
# the shipped guard: three of seven variable forms passed.
#
# The fix resolves assignments that are visible in the same command string and
# runs this same guard against the resolved text (the Check 0z pattern), so no
# new detection logic is added. A safe value stays safe once expanded, which is
# what keeps this from becoming "block anything with a $".
#
# ORDER MATTERS: Check 0x has to sit before Check 0y. Check 0y returns 0 when no
# destructive verb appears outside quotes, and `CMD="rm -rf /"; $CMD` has none —
# so a version placed after 0y never reached the substitution at all. The
# false-positive protection of 0y still applies, because the child process runs
# the full file including 0y against the resolved text.
#
# Values that only exist at runtime (environment variables inherited from the
# parent) cannot be resolved statically. That hole stays, and is documented
# rather than asserted.

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
echo "destructive-guard-variable-target"

# --- the assignment is visible in the same command string --------------------
want_block "D=/etc; ${RM}\$D"
want_block "D=/; ${RM}\"\$D\""
want_block "D=/var; ${RM}\${D}"
want_block "CMD=\"${RM}/\"; \$CMD"
want_block "TARGET=/var; sudo ${RM}\$TARGET"
want_block "P='/etc'; ${RM}\$P"

# --- named environment variables whose value is known ------------------------
want_block "${RM}\$HOME"
want_block "${RM}\${HOME}"
want_block "${RM}\"\$HOME\""

# --- controls: wrappers already closed (a break here means the harness moved) -
want_block "eval \"${RM}/etc\""
want_block "sh -c \"${RM}/etc\""

# --- controls: a safe value stays safe once expanded -------------------------
want_allow "D=./build; ${RM}\$D"
want_allow "D=node_modules; ${RM}\$D"
want_allow "OUT=dist; ${RM}\"\$OUT\""
want_allow "${RM}\$TMPDIR/work"

# --- controls: mentioning is still not running -------------------------------
want_allow "echo \"${RM}\$HOME\""
want_allow "D=/etc; echo \"${RM}\$D\""
want_allow "grep -rn '\$D' ."

# --- controls: ordinary commands ---------------------------------------------
want_allow "ls -la"
want_allow "npm ci && npm run build"

echo
echo "destructive-guard-variable-target: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
