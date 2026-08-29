#!/bin/bash
# boundary.sh — take one thing your hook is meant to refuse, and fire the hook
# at the neighbours of that thing.
#
# Why this exists: fire.sh answers "does the guard refuse this exact operation".
# That is necessary and it is not enough. Every path-matching guard draws a
# border, and the holes are never in the middle of the protected area - they
# are just outside the border, on names nobody thought to type. A guard that
# refuses ~/.ssh/id_rsa and allows ~/.ssh/id_rsa.bak is not protecting the key,
# because the backup of a key is the key.
#
# The second half matters as much as the first. A guard that refuses everything
# is not safe, it is unusable, and you only find out you have built one by
# firing it at things it must let through. So this prints both directions.
#
# Usage:
#   ./boundary.sh <hook-script> <tool-name> <field> <value> [--bare]
#
# Examples:
#   ./boundary.sh ~/.claude/hooks/key-guard.sh Read file_path /home/me/.ssh/id_rsa
#   ./boundary.sh ~/.claude/hooks/env-guard.sh Read file_path /home/me/app/.env
#
# What it prints, per neighbour:
#   refused / allowed / hook error, and a note where the answer is not a matter
#   of taste. It deliberately does NOT score you pass/fail on the ambiguous
#   rows: whether /tmp/id_rsa should be refused is your policy, not ours.
#
# Every run uses a throwaway HOME, and no file is ever read - the hook is judged
# on the tool-call arguments alone, which is all a PreToolUse hook ever sees.
# That means the paths below do not need to exist, and no real key is touched.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
BARE=""
ARGS=()
for a in "$@"; do
  if [ "$a" = "--bare" ]; then BARE="--bare"; else ARGS+=("$a"); fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [ $# -lt 4 ]; then
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

HOOK="$1"; TOOL="$2"; FIELD="$3"; VALUE="$4"
[ -f "$HOOK" ] || { echo "boundary.sh: no such hook: $HOOK" >&2; exit 64; }

dir=$(dirname "$VALUE")
base=$(basename "$VALUE")
stem="${base%.*}"
ext=""
case "$base" in *.*) ext=".${base##*.}" ;; esac

# Neighbours are grouped by what the answer means, not by how they are spelled.
#   must   - refusing this is the whole point; allowing it is a hole
#   should - a copy of a secret is a secret; allowing it is almost always a hole
#   allow  - refusing this makes the guard unusable
#   policy - reasonable people differ; printed for your eyes, not scored
CASES=()
add() { CASES+=("$1|$2|$3"); }

add must   "the thing itself"                 "$VALUE"
add should "backup, dot suffix"               "${VALUE}.bak"
add should "backup, word suffix"              "${VALUE}_old"
add should "backup, editor style"             "${VALUE}~"
add should "backup, two suffixes"             "${VALUE}.old.2"
add should "same name, uppercased"            "${dir}/$(printf '%s' "$base" | tr '[:lower:]' '[:upper:]')"
add should "same file, redundant dot segment" "${dir}/./${base}"
add should "same file, trailing space"        "${VALUE} "
add policy "same name, another directory"     "/tmp/${base}"
add policy "the directory itself"             "${dir}/"
add policy "relative path"                    "$(printf '%s' "$VALUE" | sed 's#^/[^/]*/[^/]*/##')"
# .pub is checked whether or not the target has an extension: for key files it
# is the single most common false positive, and id_rsa has no extension at all.
if [ -n "$ext" ]; then
  add allow "public half, .pub"               "${dir}/${stem}.pub"
else
  add allow "public half, .pub"               "${VALUE}.pub"
fi
add allow  "prose that names it"              "${dir}/${stem}.md"
add allow  "source file that names it"        "${dir}/${stem}_generator.py"
add allow  "an ordinary project file"         "${dir}/README.md"

printf 'hook  : %s\n' "$HOOK"
printf 'tool  : %s   field: %s\n' "$TOOL" "$FIELD"
printf 'target: %s\n' "$VALUE"
[ -n "$BARE" ] && printf 'mode  : --bare (no jq, no python3, no node)\n'
printf '\n%-6s  %-30s  %-8s  %s\n' "GROUP" "NEIGHBOUR" "RESULT" "VALUE"
printf -- '------  ------------------------------  --------  -----\n'

holes=0; overreach=0; errors=0
for c in "${CASES[@]}"; do
  group="${c%%|*}"; rest="${c#*|}"
  label="${rest%%|*}"; val="${rest#*|}"
  ${BARE:+:} true   # keep shellcheck quiet about the optional flag
  out=$(bash "$HERE/fire.sh" ${BARE:+--bare} "$HOOK" "$TOOL" "$FIELD=$val" 2>&1)
  code=$?
  case "$code" in
    2) result="refused" ;;
    0) result="allowed" ;;
    *) result="ERROR($code)"; errors=$((errors + 1)) ;;
  esac
  case "$group:$result" in
    must:allowed|should:allowed)   result="$result  <- hole"; holes=$((holes + 1)) ;;
    allow:refused)                 result="$result  <- over"; overreach=$((overreach + 1)) ;;
  esac
  printf '%-6s  %-30s  %-8s  %s\n' "$group" "$label" "$result" "$val"
done

printf '\n'
printf 'holes     : %d   (must/should rows the hook let through)\n' "$holes"
printf 'overreach : %d   (allow rows the hook refused)\n' "$overreach"
[ "$errors" -gt 0 ] && printf 'errors    : %d   (the hook itself failed; it is not protecting you either)\n' "$errors"
printf '\n'
printf 'The "policy" rows are not counted either way. Whether a key outside\n'
printf '~/.ssh, or the directory itself, should be refused is your decision.\n'
if [ "$holes" -eq 0 ] && [ "$overreach" -eq 0 ]; then
  printf '\nNothing to fix on these neighbours. That is worth knowing, and it is\n'
  printf 'not proof the guard is complete - it is proof it survives these rows.\n'
fi
[ "$holes" -gt 0 ] && exit 1
exit 0
