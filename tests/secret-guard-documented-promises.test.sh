#!/bin/bash
# secret-guard: are the two promises in its own header actually implemented?
#
# Why this exists. The header has said, since the first release, that the hook
# blocks `git add *secret*` and that CC_SECRET_PATTERNS adds patterns to block.
# Measured 2026-09-04 against the shipped scripts.json: the credential regex was
# (credentials|\.pem|\.key|\.p12|\.pfx|id_rsa|id_ed25519) -- no `secret` -- and
# the body never referenced CC_SECRET_PATTERNS at all. So `git add secrets.yaml`
# exited 0, and an operator who set CC_SECRET_PATTERNS got no error and no
# enforcement.
#
# That is the expensive direction of wrong. A guard that fails to block is
# silent: nothing breaks, no issue is filed, and the operator keeps believing
# the header. These assertions pin both promises, in both directions -- the new
# patterns must block, and ordinary staging must still pass, because a guard
# that blocks everything is uninstalled within a day.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$(mktemp)"
trap 'rm -f "$HOOK"' EXIT
python3 -c "
import json,sys
sys.stdout.write(json.load(open('$ROOT/scripts.json'))['secret-guard'])" > "$HOOK"

PASS=0; FAIL=0
WORK="$(mktemp -d)"
trap 'rm -f "$HOOK"; rm -rf "$WORK"' EXIT

run() { # run <command> -> ERR/CODE  (cwd is a clean dir with no .env)
  local payload
  payload=$(python3 -c "
import json,sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}}))" "$1")
  ERR=$(printf '%s' "$payload" | (cd "$WORK" && bash "$HOOK") 2>&1 >/dev/null)
  CODE=$?
}

check() { # check <name> <command> <expected-code>
  run "$2"
  if [ "$CODE" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    echo "        command:  $2"
    echo "        expected exit $3, got $CODE"
    [ -n "$ERR" ] && echo "        stderr:   $(printf '%s' "$ERR" | head -1)"
  fi
}

echo "secret-guard: documented promises"

# Promise 1 -- the header says *secret* is blocked.
check "secrets.yaml is blocked"          "git add secrets.yaml"        2
check "config/secret.json is blocked"    "git add config/secret.json"  2
check "SECRETS.env is blocked"           "git add SECRETS.env"         2

# The built-ins the header already delivered must keep working.
check ".env still blocked"               "git add .env"                2
check "credentials.json still blocked"   "git add credentials.json"    2
check "id_rsa still blocked"             "git add id_rsa"              2

# The other direction. A guard that blocks ordinary work gets removed.
check "ordinary source passes"           "git add src/app.js"          0
check "package.json passes"              "git add package.json"        0
check "non-add git passes"               "git status"                  0

# Promise 2 -- CC_SECRET_PATTERNS is documented as configuration.
patterns_case() { # patterns_case <name> <patterns> <command> <expected>
  local payload
  payload=$(python3 -c "
import json,sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}}))" "$3")
  local code
  printf '%s' "$payload" | (cd "$WORK" && CC_SECRET_PATTERNS="$2" bash "$HOOK") >/dev/null 2>&1
  code=$?
  if [ "$code" = "$4" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1 (CC_SECRET_PATTERNS=$2, expected exit $4, got $code)"
  fi
}

patterns_case "extra literal pattern blocks"   ".npmrc"        "git add .npmrc"          2
patterns_case "extra glob pattern blocks"      "*.jks"         "git add release.jks"     2
patterns_case "unrelated file still passes"    ".npmrc"        "git add README.md"       0
patterns_case "empty value changes nothing"    ""              "git add README.md"       0
# A malformed value must not become an approval for the built-ins. This is the
# fail-open direction that matters: the operator typed something wrong and the
# .env check has to survive it.
patterns_case "built-ins survive junk value"   "[[[:*("        "git add .env"            2
patterns_case "junk value blocks nothing new"  "[[[:*("        "git add README.md"       0

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
