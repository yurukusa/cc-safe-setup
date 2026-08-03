#!/bin/bash
# chown-guard named /etc, /var, /usr ... but never the filesystem root itself.
#
# `chown -R nobody /` rewrites ownership of every file on the machine — the worst
# form the hook exists to stop — and it walked straight through, because the
# system-directory pattern lists subdirectories of / and requires one of them.
# Measured 2026-08-03: 3 of 8 destructive forms blocked before, 8 of 8 after,
# with 0 false positives on 6 ordinary commands in both versions.
#
# The shape is the recurring one in this repo: a rule that describes the paths
# people usually type, rather than the thing that makes the command dangerous.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/examples/chown-guard.sh"
PASS=0; FAIL=0

run() {                      # <command> → exit code
  local T; T="$(mktemp -d)"
  python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},
                  "cwd":sys.argv[2],"session_id":"t"}))' "$1" "$T" \
    | HOME="$T" bash "$HOOK" >/dev/null 2>&1
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

echo "chown-guard-filesystem-root"

# --- the root itself, in the forms people actually type --------------------
want_block 'chown -R nobody /'
want_block 'chown -R nobody:nobody /'
want_block 'sudo chown -R www-data /'
want_block 'chown nobody /'
want_block 'chown -R user /*'

# --- what already worked, kept working -------------------------------------
want_block 'chown -R root /home/foo'
want_block 'chown -R nobody /etc'
want_block 'chown -R nobody ~'

# --- controls: ordinary work must stay untouched ---------------------------
# Without these, "blocks the root" and "blocks every chown" look identical.
want_allow 'chown -R me:me ./build'
want_allow 'chown me file.txt'
want_allow 'chown -R node /app/node_modules'
want_allow 'chown -R me:me src/'
want_allow 'ls -la /'
want_allow 'echo "chown -R nobody /" >> notes.md'

echo
echo "chown-guard-filesystem-root: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
