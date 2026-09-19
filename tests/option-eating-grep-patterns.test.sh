#!/bin/bash
# Are there any regexes that grep will eat as options instead of matching?
#
# Why this exists. On 2026-09-20 two shipped guards were found to have never
# fired once since they were written on 2026-03-29:
#
#   examples/bash-secret-output-detector.sh
#     grep -qE '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
#   examples/ci-workflow-guard.sh
#     grep -qE '--no-verify|--skip-tests|--no-check|SKIP_CI|skip ci|\[ci skip\]'
#
# Both patterns start with a dash. grep reads them as options, exits non-zero
# with "unrecognized option", and the surrounding `if` is false for every input
# the guard will ever see. The rule is not weak - it is absent. The fix is two
# characters: `--` before the pattern, or `-e`.
#
# This class is invisible from three directions at once, which is why it lived
# for five and a half months:
#   - the guard still exits 0, so anything asserting on exit codes stays green;
#   - grep's complaint goes to the hook's stderr, which nobody reads on a hook
#     that is behaving itself;
#   - a neighbouring rule may share a token with the dead one, so a manual
#     spot-check produces a warning and the operator stops looking.
#
# So this test does not check behaviour. It checks shape, across every shell
# file we ship *and* the two JSON files that carry inline guard commands - the
# JSON is what actually runs on an operator's machine, so leaving it out would
# check the copy and not the original.
#
# A detector that finds nothing proves nothing until you have seen it find
# something, so the positive and negative controls below run first. If the
# controls fail, the clean result on the real tree means nothing and this test
# fails loudly rather than passing quietly.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A quoted grep pattern whose first character is a dash. The quote may be
# backslash-escaped, because the same commands appear inline inside JSON.
BAD_SHAPE='grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*\\?['"'"'"]-'
# ... unless `--` or `-e` comes first, which is exactly the correct spelling.
OK_SHAPE='grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(--|-e)[[:space:]]'

# scan <path...> - print "file:line:text" for each option-eating grep call.
#
# Comment lines are skipped: this file, and several tests, quote the broken
# patterns on purpose.
#
# `*selftest*.sh` is skipped for the same reason, one level up. A selftest's job
# is to build something broken and prove the detector sees it, so the fixtures
# inside one are deliberately unfirable rules. A shape-based scan cannot tell
# "broken" from "broken on purpose", and the first CI run of this suite caught
# audit/unfirable-selftest.sh - correctly, and uselessly. The cost of the
# exclusion is real and worth stating: a genuine defect written inside a file
# whose name contains "selftest" will not be reported here. Nothing we install
# as a guard is named that way.
scan() {
  local out
  out=$(grep -rnE --include='*.sh' --include='*.json' --exclude='*selftest*.sh' \
        -- "$BAD_SHAPE" "$@" 2>/dev/null) || true
  printf '%s' "$out" \
    | grep -vE -- "$OK_SHAPE" \
    | grep -vE -- '^[^:]+:[0-9]+:[[:space:]]*#' \
    | grep -v '^$'
}

# --- positive control: the detector must find both spellings ----------------
mkdir -p "$TMP/bad"
cat > "$TMP/bad/guard.sh" <<'BAD'
#!/bin/bash
if echo "$1" | grep -qE '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'; then
  echo "secret" >&2
fi
BAD
cat > "$TMP/bad/inline.json" <<'BADJSON'
{"command": "if echo \"$X\" | grep -qE \"--no-verify|SKIP_CI\"; then echo hi; fi"}
BADJSON
n=$(scan "$TMP/bad" | wc -l)
if [ "$n" -eq 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: positive control found $n, expected 2 - the detector is broken,"
  echo "        so a clean result on the real tree would prove nothing"
  scan "$TMP/bad" | sed 's/^/        /'
fi

# --- negative control: correct spellings must not be reported ---------------
mkdir -p "$TMP/good"
cat > "$TMP/good/guard.sh" <<'GOOD'
#!/bin/bash
# a dashed pattern is fine once it is separated from the options
if echo "$1" | grep -qE -- '-----BEGIN (RSA |EC )?PRIVATE KEY-----'; then :; fi
if echo "$1" | grep -qE -e '--no-verify|SKIP_CI'; then :; fi
if echo "$1" | grep -qE 'dangerously-skip-permissions|--force'; then :; fi
GOOD
n=$(scan "$TMP/good" | wc -l)
if [ "$n" -eq 0 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: negative control found $n, expected 0 - correct spellings are"
  echo "        being reported, which would make this test unusable"
  scan "$TMP/good" | sed 's/^/        /'
fi

# --- the real assertion -----------------------------------------------------
TARGETS=""
for p in examples audit scripts hooks/hooks.json scripts.json; do
  [ -e "$REPO/$p" ] && TARGETS="$TARGETS $REPO/$p"
done

# shellcheck disable=SC2086
found=$(scan $TARGETS)

if [ -z "$found" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: patterns that grep will read as options:"
  printf '%s\n' "$found" | sed 's/^/        /'
  echo "        Fix: put -- before the pattern, or use -e."
fi

echo "option-eating-grep-patterns: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
