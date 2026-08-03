#!/bin/bash
# A settings.json that exists but does not parse must never be treated as {}.
#
# The installer read it with a bare JSON.parse in 34 places, swallowed the failure
# outright in 9, and in 6 of those 9 wrote the resulting object straight back with
# writeFileSync(SETTINGS_PATH, ...). Every hook, permission and env var the user had
# was replaced by a fresh object holding only the hook just added — and the command
# exited 0, printing "Registered in settings.json".
#
# The usual trigger is a snippet copied from docs whose first line is
# `// path/to/file`, which is not legal JSON. This repo shipped four such examples.
#
# Also covered here: --protect used to throw ReferenceError on every single run
# (protect() called rules.some(...) and `rules` never existed in that function), so
# the hook file was written and never registered. Nothing in tests/ exercised
# --protect at all, which is why it could stay broken.
#
# Every case runs in a throwaway HOME. Nothing touches the real one.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

BROKEN='// ~/.claude/settings.json
{
  "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "keep-me-guard.sh" } ] } ] },
  "permissions": { "allow": ["Bash(ls:*)"] },
  "env": { "KEEP_ME": "1" }
}'
VALID='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"keep-me-guard.sh"}]}]},"env":{"KEEP_ME":"1"}}'

# check <name> <settings body> <expected exit> <must survive: 1|0> <expect warning: 1|0> <args...>
check() {
  local name="$1" body="$2" want_rc="$3" want_keep="$4" want_warn="$5"; shift 5
  local T; T="$(mktemp -d)"
  mkdir -p "$T/.claude/hooks"
  printf '%s' "$body" > "$T/.claude/settings.json"

  local out rc
  out="$(cd "$ROOT" && HOME="$T" node index.mjs "$@" 2>&1)"; rc=$?

  local keep=0
  grep -q 'keep-me-guard' "$T/.claude/settings.json" && \
    grep -q 'KEEP_ME' "$T/.claude/settings.json" && keep=1
  local warn=0
  case "$out" in *'is not valid JSON'*) warn=1 ;; esac

  if [ "$rc" -eq "$want_rc" ] && [ "$keep" -eq "$want_keep" ] && [ "$warn" -eq "$want_warn" ]; then
    PASS=$((PASS+1)); echo "  ok   $name"
  else
    FAIL=$((FAIL+1))
    echo "  FAIL $name"
    echo "       exit     want=$want_rc got=$rc"
    echo "       survived want=$want_keep got=$keep"
    echo "       warned   want=$want_warn got=$warn"
    echo "$out" | tail -4 | sed 's/^/       | /'
  fi
  find "$T" -mindepth 1 -delete 2>/dev/null; rmdir "$T" 2>/dev/null
}

echo "settings-unreadable-refuses-to-write"

# --- the file is unreadable: refuse to write, keep everything ---------------
check "guard: broken settings is not overwritten" \
  "$BROKEN" 1 1 1 --guard "block rm -rf"
check "protect: broken settings is not overwritten" \
  "$BROKEN" 1 1 1 --protect .env

# --- controls: a readable file must behave exactly as before ----------------
# Without these, "refuses to write" and "cannot write at all" look the same.
check "guard: valid settings still registers" \
  "$VALID" 0 1 0 --guard "block rm -rf"
check "protect: valid settings still registers" \
  "$VALID" 0 1 0 --protect .env

# --- --protect used to throw ReferenceError before it could register --------
T="$(mktemp -d)"; mkdir -p "$T/.claude/hooks"
printf '%s' "$VALID" > "$T/.claude/settings.json"
out="$(cd "$ROOT" && HOME="$T" node index.mjs --protect .env 2>&1)"
if echo "$out" | grep -q 'ReferenceError'; then
  FAIL=$((FAIL+1)); echo "  FAIL protect: no ReferenceError"
  echo "$out" | tail -3 | sed 's/^/       | /'
else
  PASS=$((PASS+1)); echo "  ok   protect: no ReferenceError"
fi
if grep -q 'Edit|Write' "$T/.claude/settings.json"; then
  PASS=$((PASS+1)); echo "  ok   protect: registered under the Edit|Write matcher"
else
  FAIL=$((FAIL+1)); echo "  FAIL protect: registered under the Edit|Write matcher"
fi
find "$T" -mindepth 1 -delete 2>/dev/null; rmdir "$T" 2>/dev/null

echo
echo "settings-unreadable-refuses-to-write: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
