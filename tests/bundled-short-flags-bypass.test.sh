#!/bin/bash
# Bundled short flags slipped past the force checks
#
# Short options can be written together. These are all one flag group:
#
#   git push -uf origin feature     # -u --set-upstream  +  -f --force
#   git checkout -bf main           # -b new branch      +  -f force
#   git switch -Cf main             # -C force-create    +  -f force
#
# Every one of them is a real destructive operation. The shipped patterns
# looked for the spelling `-f` as a standalone word (`-f\b`), so a bundled
# group never matched and the guards exited 0 -- an affirmative approval.
#
# Measured 2026-09-03 against the shipped copies: 4 bypasses.
#   branch-guard      git push -uf   (force push, any branch)
#   destructive-guard git checkout -bf, git switch -Cf, git checkout -qf
#
# The fix reads "a dash, then letters, ending in f" instead of the literal
# `-f`: [^A-Za-z0-9]-[a-zA-Z]*f\b
#
# The leading [^A-Za-z0-9] is what keeps `--follow-tags` out: after the second
# dash the letters run `follow`, and `f` is not at a word boundary there.
#
# destructive-guard needed a second change beyond the character class. Its
# pattern was `git\s+(checkout|switch)\s+.*`, and that `\s+` ate the space in
# front of `-bf`, leaving no character for [^A-Za-z0-9] to match. Anchoring on
# `\b` instead of `\s+` leaves the space in the subject where the class can see
# it. Same shape as the git-globals fix: the check was right, the thing feeding
# it was not.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG=$(mktemp); DG=$(mktemp)
trap 'rm -f "$BG" "$DG"' EXIT
python3 -c "
import json,sys
d=json.load(open('$ROOT/scripts.json'))
open('$BG','w').write(d['branch-guard'])
open('$DG','w').write(d['destructive-guard'])"

PASS=0; FAIL=0

check() {
    local guard="$1" desc="$2" cmd="$3" want="$4"   # want: 2 = blocked, 0 = allowed
    local payload code
    payload=$(python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
    printf '%s' "$payload" | bash "$guard" >/dev/null 2>&1
    code=$?
    if [ "$code" = "$want" ]; then
        echo "PASS: $desc"; PASS=$((PASS+1))
    else
        echo "FAIL: $desc (expected exit $want, got $code)"; FAIL=$((FAIL+1))
    fi
}

# --- branch-guard: bundled -f in a push ---
check "$BG" "bg: -uf force push"              'git push -uf origin feature'         2
check "$BG" "bg: -qf force push"              'git push -qf origin feature'         2
check "$BG" "bg: -uf with a global"           'git -C /repo push -uf origin feature' 2
check "$BG" "bg: plain -f still blocked"      'git push -f origin feature'          2
check "$BG" "bg: --force still blocked"       'git push --force origin feature'     2

# --- branch-guard: ordinary work still goes through ---
check "$BG" "bg: --follow-tags allowed"       'git push --follow-tags origin feature' 0
check "$BG" "bg: -u alone allowed"            'git push -u origin feature'          0
check "$BG" "bg: plain push allowed"          'git push origin feature'             0

# --- destructive-guard: bundled -f in checkout/switch ---
check "$DG" "dg: checkout -bf"                'git checkout -bf main'               2
check "$DG" "dg: switch -Cf"                  'git switch -Cf main'                 2
check "$DG" "dg: checkout -qf"                'git checkout -qf main'               2
check "$DG" "dg: checkout -f still blocked"   'git checkout -f main'                2
check "$DG" "dg: checkout --force blocked"    'git checkout --force main'           2
check "$DG" "dg: switch --discard-changes"    'git switch --discard-changes main'   2

# --- destructive-guard: ordinary work still goes through ---
check "$DG" "dg: checkout a branch"           'git checkout main'                   0
check "$DG" "dg: checkout -b new branch"      'git checkout -b feature'             0
check "$DG" "dg: switch -c new branch"        'git switch -c my-feature'            0
check "$DG" "dg: switch --detach"             'git switch --detach HEAD'            0
check "$DG" "dg: checkout --track"            'git checkout --track origin/feature' 0

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
