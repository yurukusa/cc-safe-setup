#!/bin/bash
# No user-facing string may assert that the operator is protected.
#
# On 2026-09-03 four separate places in this project made the same claim, and
# all four were wrong in the direction that costs most:
#
#   --audit              "No risks detected. Your setup looks solid."
#   --audit --ci         a CI gate whose exit code could not be non-zero
#   install (default)    "You are now protected against:" over rm -rf, force-push, .env
#   install (--shield)   "Your Claude Code sessions are now protected."
#   docs/index.html      a share button offering "Fully protected with safety hooks"
#
# Every one of them was produced by reading configuration. None of them had read
# the operator's session history, where the answer actually lives: most guards
# here match the start of the command string, and on the machine this was
# written on 89.1% of Bash calls are compound and 32.0% begin with `cd`.
# branch-guard.sh examined 50 of 383 `git push` calls.
#
# The point of this test is that "be careful about overclaiming" is not a
# control. Four instances survived months of review because nothing checked for
# them. This checks.
#
# The rule: a user-facing string may say what was checked, what was installed,
# or what a guard is aimed at. It may not say the operator is protected, safe,
# covered or solid, because this project cannot know that from configuration.
# If a future check does read the history and can support such a claim, add it
# to the allowed list below with the reason.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Phrases that assert a state of safety rather than reporting an action taken.
BANNED=(
  "you are now protected"
  "are now protected"
  "fully protected"
  "looks solid"
  "completely safe"
  "no risks detected"
  "guaranteed safe"
  "prevents all"
  "blocks all"
)

# Comment lines are exempt: the corrections above quote the old wording on
# purpose, so that the next reader knows what was retracted and why. A comment
# cannot reach a user.
strip_comments() {
  grep -vE "^[[:space:]]*(//|#|\*|<!--)"
}

# A banned phrase can appear legitimately when it describes a failure mode
# rather than promising one. "A broken hook blocks ALL tools" is a warning: it
# tells the reader something bad happens, which is the opposite of reassurance.
# Each exception is listed with its reason so the next reader can disagree.
ALLOWED=(
  "A syntax error exit 2 blocks ALL tools"      # warns that a broken hook halts everything
  "Bash syntax error = blocks ALL tools"        # same warning, on the mistakes page
)

is_allowed() { # line
  for a in "${ALLOWED[@]}"; do
    case "$1" in *"$a"*) return 0 ;; esac
  done
  return 1
}

scan() { # file
  local f="$1" found=0
  for phrase in "${BANNED[@]}"; do
    local hits
    local raw kept=""
    raw="$(strip_comments < "$f" | grep -in -- "$phrase" || true)"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      is_allowed "$line" || kept="${kept}${line}"$'\n'
    done <<< "$raw"
    hits="$(printf '%s' "$kept")"
    if [ -n "$hits" ]; then
      found=1
      echo "  FAIL: ${f#$REPO/} asserts safety: \"$phrase\""
      printf '%s\n' "$hits" | head -3 | sed 's/^/        /'
    fi
  done
  return $found
}

TARGETS=("$REPO/index.mjs")
while IFS= read -r h; do TARGETS+=("$h"); done < <(find "$REPO/docs" -maxdepth 1 -name '*.html' 2>/dev/null)

for f in "${TARGETS[@]}"; do
  if scan "$f"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done

# The test must be able to fail, or it is the same kind of empty gate as the one
# it was written for. Feed it a string that must trip.
PROBE="$(mktemp)"
printf 'console.log("You are now protected against everything");\n' > "$PROBE"
if scan "$PROBE" >/dev/null 2>&1; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: the scanner did not catch a planted claim — it cannot fail"
else
  PASS=$((PASS + 1))
fi
rm -f "$PROBE"

echo "  no-unqualified-safety-claims: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
