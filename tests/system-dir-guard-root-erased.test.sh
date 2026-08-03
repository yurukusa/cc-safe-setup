#!/bin/bash
# system-dir-protection-guard named the root and then erased it before checking.
#
#     path="${path%/}"          # "remove trailing slash"
#     case "$path" in
#         /|/home|/etc|/usr|…)  # the `/` branch the author did write
#
# `${path%/}` turns "/" into "", so the `/` branch was unreachable. `/etc` was
# blocked, `/` was not. Measured 2026-08-03: `rm -rf /`, `mv / /tmp/x` and
# `chmod -R 777 /` all walked through, while every subdirectory of / was stopped.
#
# The fix is one condition: do not strip the slash when the path *is* the root.
# Found by asking which other hooks name subdirectories of / but never / itself,
# right after the same shape was fixed in chown-guard.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/examples/system-dir-protection-guard.sh"
PASS=0; FAIL=0

run() {
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

echo "system-dir-guard-root-erased"

# --- the root itself, across the three operations this guard covers ---------
want_block 'rm -rf /'
want_block 'sudo rm -rf /'
want_block 'mv / /tmp/x'
want_block 'chmod -R 777 /'
want_block 'chown -R nobody /'

# --- what already worked, kept working -------------------------------------
want_block 'rm -rf /etc'
want_block 'rm -rf /usr/lib'
want_block 'mv /var /tmp/x'

# --- controls: ordinary work must stay untouched ---------------------------
# Without these, "blocks the root" and "blocks everything" look identical.
want_allow 'ls -la /'
want_allow 'cat /etc/hosts'
want_allow 'rm -rf ./build'
want_allow 'mv ./dist ./dist.bak'
want_allow 'chmod -R 755 ./scripts'

echo
echo "system-dir-guard-root-erased: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
