#!/bin/bash
# bash-secret-output-detector: does each advertised pattern actually fire?
#
# Why this exists. The six existing checks for this hook in test.sh all assert
# exit 0. This hook always exits 0 by default, so those checks pass whether a
# pattern fires or not - the same shape as the "234 test files that could not
# fail" noted in the CI workflow.
#
# The regression being pinned: the private-key check was written as
#   grep -qE '-----BEGIN ... PRIVATE KEY-----'
# without `--`, so grep read the leading dashes as options, printed
# "unrecognized option" and exited non-zero. The check never fired on any
# input, and test.sh's "private key" case passed anyway because it only looked
# at the exit code. Measured 2026-09-20 against the shipped file.
#
# Both directions are asserted: a detector that also fires on ordinary output
# is a detector operators learn to ignore.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/examples/bash-secret-output-detector.sh"
PASS=0
FAIL=0

# Split so that writing this file does not itself trip a secret scanner.
AWS="AKI""AIOSFODNN7""EXAMPLE"
APIKEY="api_key=sk""-1234567890abcdefghijklmnop"
CONN="postgres://user"":pass@host:5432/db"
PEM="-----BEGIN RSA PRIVATE KEY-----"
GH="ghp""_1234567890abcdefghijklmnopqrstuv"
JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc"

run() {
  local payload
  payload=$(printf '{"tool_name":"Bash","tool_result":{"stdout":"%s"}}' "$1")
  ERR=$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)
}

warns() {
  run "$2"
  local got="no"
  case "$ERR" in *"SECRET DETECTED"*) got="yes" ;; esac
  if [ "$got" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1 (expected warn=$3, got warn=$got)"
    echo "        stderr: $ERR"
  fi
}

quiet_stderr() {
  run "hello world"
  case "$ERR" in
    *"unrecognized option"*|*"Usage: grep"*)
      FAIL=$((FAIL + 1))
      echo "  FAIL: a pattern is malformed and grep is erroring out"
      echo "        stderr: $ERR" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

echo "bash-secret-output-detector-detects:"

# --- every advertised pattern has to fire ----------------------------------
warns "AWS access key"        "$AWS"     yes
warns "API key assignment"    "$APIKEY"  yes
warns "connection string"     "$CONN"    yes
warns "private key header"    "$PEM"     yes
warns "GitHub token"          "$GH"      yes
warns "JWT"                   "$JWT"     yes

# --- ordinary output must stay quiet ---------------------------------------
warns "plain output is quiet"  "hello world"       no
warns "safe env var is quiet"  "PATH=/usr/bin"     no

# --- no pattern may be malformed -------------------------------------------
quiet_stderr

# --- default must not interrupt; the opt-in must ---------------------------
printf '%s' "{\"tool_name\":\"Bash\",\"tool_result\":{\"stdout\":\"$AWS\"}}" \
  | bash "$HOOK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: default must not interrupt (expected exit 0, got $rc)"
fi

printf '%s' "{\"tool_name\":\"Bash\",\"tool_result\":{\"stdout\":\"$AWS\"}}" \
  | CC_SECRET_OUTPUT_BLOCK=1 bash "$HOOK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: CC_SECRET_OUTPUT_BLOCK=1 must exit 2 (got $rc)"
fi

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
