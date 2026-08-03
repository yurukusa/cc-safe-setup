#!/bin/bash
# destructive-guard read one operand of rm and then spoke for the whole line.
#
# Check 1 keys on the position right after the flags, so a safe target in front
# hides a dangerous one behind it:
#
#     rm -rf ..                 blocked
#     rm -rf node_modules ..    NOT blocked   <- deletes the parent directory
#
# Measured 2026-08-03 against the shipped core. This is the same shape as the
# fifteen approving hooks fixed the same day: a rule that examines one command
# position and then applies its verdict to everything else on the line.
#
# Check 1b scans every operand. It is deliberately narrow — only `..`, `/` and
# `~`, which cannot be meant in an ordinary cleanup — so it cannot start blocking
# work like `rm -rf build ./dist` or `rm -rf ../sibling/node_modules`.

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
echo "destructive-guard-every-operand"

# --- the dangerous operand behind a safe one -------------------------------
want_block "$RM -rf node_modules .."
want_block "$RM -r -f node_modules .."
want_block "$RM -rf dist build .."
want_block "$RM -rf coverage ~"

# --- and in the first position, which already worked -----------------------
want_block "$RM -rf .."
want_block "$RM -rf ../"

# --- controls: ordinary cleanup must stay untouched ------------------------
# Without these, "checks every operand" and "blocks every rm" look identical.
want_allow "$RM -rf node_modules"
want_allow "$RM -rf ./build"
want_allow "$RM -rf dist coverage"
want_allow "$RM -rf build/*"
want_allow "$RM -rf ../sibling-project/node_modules"
want_allow "$RM -f package-lock.json"
want_allow "cd app && $RM -rf node_modules && npm ci"
want_allow "ls -la .."
want_allow "cp -r .. /tmp/backup"

echo
echo "destructive-guard-every-operand: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
