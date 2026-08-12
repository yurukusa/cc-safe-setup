#!/bin/bash
# output-secret-mask: does the warning actually fire, and only when it should?
#
# Why this exists. The eight existing checks for this hook in test.sh all assert
# exit 0. This hook *always* exits 0 — it only writes to stderr — so those checks
# pass whether the warning fires or not. They cannot fail on the behaviour that
# matters, which is the same shape as the "234 test files that could not fail"
# noted in the CI workflow. These assert on stderr instead.
#
# The regression being pinned: the OpenAI pattern used to be written without a
# left boundary, so ordinary English words ending in "sk" before a separator
# (task-, ask-, risk-, disk-, desk-) matched and the hook cried on ordinary
# output. A warning that fires on normal paths is a warning operators learn to
# ignore, which costs the whole hook.
#
# Both directions are asserted deliberately: silencing a false positive is only
# a fix if the true positive still fires.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/examples/output-secret-mask.sh"
PASS=0
FAIL=0

# Split so that writing this file does not itself trip a secret scanner.
KEY="sk""-proj-abcdefghijklmno""pqrst1234567890"
AWS="AKI""AIOSFODNN7""EXAMPLE"
ORDINARY="data/task-""management-system-config.json"

run() { # run <stdout-text> -> sets ERR
  local payload
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"cat conf"},"tool_result":{"stdout":"%s"}}' "$1")
  ERR=$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)
}

warns() { # warns <name> <text> <expect: yes|no>
  run "$2"
  local got="no"
  case "$ERR" in *WARNING*) got="yes" ;; esac
  if [ "$got" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1 (expected warn=$3, got warn=$got)"
    echo "        stderr: $ERR"
  fi
}

echo "output-secret-mask-warns:"

# --- true positives: the warning has to fire -------------------------------
warns "real key shape warns"            "$KEY"                       yes
warns "AWS key shape warns"             "$AWS"                       yes
warns "API_KEY assignment warns"        "API_KEY=abc123def456ghi"    yes

# --- false positives: the warning must stay quiet --------------------------
warns "ordinary task- path is quiet"    "$ORDINARY"                  no
warns "plain output is quiet"           "hello world"                no
warns "safe env var is quiet"           "PATH=/usr/bin"              no

# --- the hook never blocks; it only reports --------------------------------
printf '%s' "{\"tool_name\":\"Bash\",\"tool_result\":{\"stdout\":\"$KEY\"}}" \
  | bash "$HOOK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: hook must not block (expected exit 0, got $rc)"
fi

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
