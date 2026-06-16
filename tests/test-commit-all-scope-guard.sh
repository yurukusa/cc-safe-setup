#!/bin/bash
# Tests for commit-all-scope-guard.sh
# Absolute path: tests cd into scratch repos, so a relative path would break.
HOOK="$(cd "$(dirname "$0")/../examples" && pwd)/commit-all-scope-guard.sh"
PASS=0
FAIL=0

run_test() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# Build a scratch git repo with one edited tracked file and two unrelated
# work-in-progress files, then run the hook from inside it.
mkrepo() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/cc-commit-scope-test.XXXXXX")
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && echo base > a.txt && git add a.txt && git commit -qm init \
    && echo edit > a.txt && echo wip > b.txt && echo wip > c.txt )
  echo "$d"
}

# Run hook in $1 dir with command $2; print "exit|stderr_lines".
run_in() {
  local dir="$1" cmd="$2" err rc
  err=$(cd "$dir" && printf '{"tool_input":{"command":"%s"}}' "$cmd" | bash "$HOOK" 2>&1 1>/dev/null)
  rc=$?
  echo "$rc|$(printf '%s' "$err" | grep -c .)"
}

echo "Testing commit-all-scope-guard.sh"
echo "================================="

# 1. git commit -am → warn (exit 0, non-empty stderr listing the swept files)
D=$(mkrepo); R=$(run_in "$D" "git commit -am rollback")
[ "${R%%|*}" = "0" ] && [ "${R##*|}" -gt 0 ] && run_test "commit -am → warns with file list" pass || run_test "commit -am → warns ($R)" fail
rm -rf "$D"

# 2. git add . → warn
D=$(mkrepo); R=$(run_in "$D" "git add .")
[ "${R%%|*}" = "0" ] && [ "${R##*|}" -gt 0 ] && run_test "git add . → warns" pass || run_test "git add . → warns ($R)" fail
rm -rf "$D"

# 3. explicit git add <path> → silent (no warning)
D=$(mkrepo); R=$(run_in "$D" "git add a.txt && git commit -m fix")
[ "${R%%|*}" = "0" ] && [ "${R##*|}" -eq 0 ] && run_test "explicit add → silent" pass || run_test "explicit add → silent ($R)" fail
rm -rf "$D"

# 4. plain git commit -m (no -a) → silent
D=$(mkrepo); R=$(run_in "$D" "git commit -m msg")
[ "${R%%|*}" = "0" ] && [ "${R##*|}" -eq 0 ] && run_test "commit -m (no -a) → silent" pass || run_test "commit -m → silent ($R)" fail
rm -rf "$D"

# 5. non-git command → silent
D=$(mkrepo); R=$(run_in "$D" "ls -la")
[ "${R%%|*}" = "0" ] && [ "${R##*|}" -eq 0 ] && run_test "non-git command → silent" pass || run_test "non-git → silent ($R)" fail
rm -rf "$D"

# 6. empty input → exit 0
EXIT=0; printf '%s' '{}' | bash "$HOOK" >/dev/null 2>&1 || EXIT=$?
[ "$EXIT" = "0" ] && run_test "empty input → exit 0" pass || run_test "empty input → exit 0 (got $EXIT)" fail

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
