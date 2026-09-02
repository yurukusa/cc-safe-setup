#!/bin/bash
# The install screen used to end with a claim it cannot support.
#
#   🛡️  Shield activated!
#   18 hooks installed and configured.
#   Your Claude Code sessions are now protected.
#
# The first two lines are facts about how many files were written. The third is
# a statement about whether the user is safe, and on a real machine it is
# usually wrong in the direction that costs most. Most of the guards this
# installs match the start of the command string (`^\s*git\s+push`), and on the
# machine this was written on 89.1% of Bash calls are compound and 32.0% begin
# with `cd` — so the guard that was just installed does not see the majority of
# what the operator actually runs. Telling them they are protected at exactly
# that moment is how a fence stops being checked.
#
# It now measures instead of asserting: a bounded read of the most recent
# transcripts, and the user's own two percentages. With no history there is
# nothing to measure, so it says what the guards match and stops — it does not
# fall back to reassurance.
#
# Fixed 2026-09-03.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    echo "    expected: $2"
    echo "    actual:   $3"
  fi
}

strip() { sed 's/\x1b\[[0-9;]*m//g'; }

# --- no history at all -------------------------------------------------------
FRESH="$(mktemp -d)"
OUT_FRESH="$(HOME="$FRESH" node "$REPO/index.mjs" --shield 2>&1 | strip)"

check "still reports what it installed" \
  "yes" "$(printf '%s' "$OUT_FRESH" | grep -q 'hooks installed and configured' && echo yes || echo no)"
check "does not claim the sessions are protected" \
  "yes" "$(printf '%s' "$OUT_FRESH" | grep -q 'are now protected' && echo no || echo yes)"
check "names the limitation even with nothing to measure" \
  "yes" "$(printf '%s' "$OUT_FRESH" | grep -q 'match the start of the command string' && echo yes || echo no)"
check "invents no percentage from an empty history" \
  "yes" "$(printf '%s' "$OUT_FRESH" | grep -qE '[0-9]+\.[0-9]% of [0-9,]+ Bash calls' && echo no || echo yes)"

# --- a history with a known shape -------------------------------------------
# 900 calls, 600 of them compound and beginning with cd. Anything below the
# 200-call floor must not produce a percentage, so the count matters as much as
# the ratio.
HIST="$(mktemp -d)"
mkdir -p "$HIST/.claude/projects/-probe"
T="$HIST/.claude/projects/-probe/session.jsonl"
: > "$T"
emit() {
  printf '{"type":"assistant","timestamp":"2026-09-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" >> "$T"
}
for i in $(seq 1 600); do emit "cd /tmp/work && git status"; done
for i in $(seq 1 300); do emit "ls /tmp/work"; done

OUT_HIST="$(HOME="$HIST" node "$REPO/index.mjs" --shield 2>&1 | strip)"

check "reports the user's own compound ratio" \
  "yes" "$(printf '%s' "$OUT_HIST" | grep -qE '66\.7% of 900 Bash calls are compound' && echo yes || echo no)"
check "reports the user's own cd ratio" \
  "yes" "$(printf '%s' "$OUT_HIST" | grep -qE '66\.7% begin with cd' && echo yes || echo no)"
check "points at the check rather than a product page" \
  "yes" "$(printf '%s' "$OUT_HIST" | grep -q 'blindspots' && echo yes || echo no)"
check "still does not claim protection once it has numbers" \
  "yes" "$(printf '%s' "$OUT_HIST" | grep -q 'are now protected' && echo no || echo yes)"

# --- too little history to say anything --------------------------------------
THIN="$(mktemp -d)"
mkdir -p "$THIN/.claude/projects/-probe"
T="$THIN/.claude/projects/-probe/session.jsonl"
: > "$T"
for i in $(seq 1 40); do emit "cd /tmp/work && git status"; done

OUT_THIN="$(HOME="$THIN" node "$REPO/index.mjs" --shield 2>&1 | strip)"
check "says nothing numeric below the sample floor" \
  "yes" "$(printf '%s' "$OUT_THIN" | grep -qE '% of [0-9,]+ Bash calls' && echo no || echo yes)"

# --- the default path (no flags) --------------------------------------------
# This is the screen most people see, and it was the more misleading of the two:
# it named the exact dangers — force-push, `.env` committed — that a
# start-anchored guard misses the moment the command arrives after a separator.
OUT_DEFAULT="$(printf 'y\n' | HOME="$HIST" node "$REPO/index.mjs" 2>&1 | strip)"

check "default path no longer claims the dangers are covered" \
  "yes" "$(printf '%s' "$OUT_DEFAULT" | grep -q 'You are now protected against' && echo no || echo yes)"
check "default path says what the guards aim at" \
  "yes" "$(printf '%s' "$OUT_DEFAULT" | grep -q 'What these guards are aimed at' && echo yes || echo no)"
check "default path still lists the dangers" \
  "yes" "$(printf '%s' "$OUT_DEFAULT" | grep -q 'Force-push to main/master' && echo yes || echo no)"
check "default path separates aim from coverage" \
  "yes" "$(printf '%s' "$OUT_DEFAULT" | grep -q 'Aimed at is not the same as covering' && echo yes || echo no)"
check "default path reports the user's own ratio" \
  "yes" "$(printf '%s' "$OUT_DEFAULT" | grep -qE '66\.7% of 900 Bash' && echo yes || echo no)"

echo "  install-does-not-claim-protection: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
