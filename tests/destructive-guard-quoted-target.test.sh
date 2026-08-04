#!/bin/bash
# Quoting the argument made the target invisible.
#
# Check 1 required the path to follow the flags directly:
#
#     rm -rf /etc        blocked
#     rm -rf "/etc"      NOT blocked   <- same deletion, one character apart
#     rm -rf '~'         NOT blocked
#
# Quoting an argument is an ordinary way to write a command — a path with a
# space in it has to be quoted — so this is not an evasion technique, it is
# what a careful user types. Measured 2026-08-04 against the shipped guard:
# five of nine quoted forms passed.
#
# Two places assumed an unquoted operand: the Check 1 pattern (one optional
# quote is now allowed in front of the path, and the terminators accept a
# closing quote) and the TARGET_PATH extraction feeding findmnt (`\S+` picked
# up the quotes, and findmnt cannot resolve a path spelled with them attached).
#
# The controls are what keep this from becoming "block anything with a quote":
# a quoted safe target must still pass, and — this is the one that matters after
# the mentions/invocations gate landed — a dangerous string quoted inside grep,
# echo, git commit or awk must still pass, because searching for a command is
# not running it.

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
echo "destructive-guard-quoted-target"

# --- the target is quoted, the deletion is real ------------------------------
want_block "${RM}\"/etc\""
want_block "${RM}'/etc'"
want_block "${RM}\"~\""
want_block "${RM}'~'"
want_block "${RM}\"/home/user\""
want_block "sudo ${RM}\"/var\""

# --- unquoted, which already worked ------------------------------------------
want_block "${RM}~"
want_block "${RM}/"
want_block "${RM}/etc"

# --- controls: a quoted safe target is still safe ----------------------------
want_allow "${RM}\"node_modules\""
want_allow "${RM}'node_modules'"
want_allow "${RM}\"./build\""
want_allow "${RM}node_modules"
want_allow "${RM}./build"

# --- controls: quoting it inside another command is still a mention ----------
want_allow "echo \"${RM}/\""
want_allow "grep -r \"${RM}/\" ."
want_allow "git commit -m \"docs: ${RM}/ warning\""
want_allow "awk '/${RM}/ {print}' h.log"
want_allow "ls -la"
want_allow "npm ci && npm run build"

echo
echo "destructive-guard-quoted-target: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
