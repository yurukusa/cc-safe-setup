#!/bin/bash
# The three git guards never saw `git -C <path> <verb>`
#
# git accepts its own options between the program name and the verb:
#
#   git -C /repo push --force
#   git -c core.pager=cat reset --hard
#   git --git-dir=/repo/.git clean -fd
#
# All three do exactly what the unprefixed form does. Every git pattern in
# branch-guard, secret-guard and destructive-guard expected the verb to sit
# directly after the word `git`, so all three hooks exited 0 -- which is an
# affirmative approval, not a shrug.
#
# Measured 2026-09-03 against the shipped copies: 10 bypasses.
#   branch-guard      git -C push to a protected branch, git -C force push,
#                     --git-dir force push, and `git push origin +branch`
#                     (a force push with no --force anywhere in it)
#   secret-guard      git -C add .env, git -C add id_rsa
#   destructive-guard git -C reset --hard, git -C clean -fd,
#                     git -C checkout --force, --git-dir reset --hard
#
# destructive-guard needed two fixes, not one. The checks themselves were only
# half of it: the mentions-vs-invocations pre-filter counted git verbs in the
# raw text, scored `git -C /repo reset --hard` as zero verbs, and exited before
# any check ran. Fixing the checks alone changed nothing measurable. Same shape,
# one layer earlier -- which is where it decided the outcome.
#
# The fix normalises the globals away once (cc_strip_git_globals) and leaves the
# patterns readable, rather than threading an optional-globals group through
# every one of them.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG=$(mktemp); SG=$(mktemp); DG=$(mktemp)
trap 'rm -f "$BG" "$SG" "$DG"' EXIT
python3 -c "
import json,sys
d=json.load(open('$ROOT/scripts.json'))
open('$BG','w').write(d['branch-guard'])
open('$SG','w').write(d['secret-guard'])
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

# --- branch-guard: globals before `push` ---
check "$BG" "bg: -C, protected branch"        'git -C /repo push origin main'              2
check "$BG" "bg: -C, force push"              'git -C /repo push origin feature --force'   2
check "$BG" "bg: --git-dir, force push"       'git --git-dir=/r/.git push --force'         2
check "$BG" "bg: -c, force push"              'git -c core.pager=cat push --force'         2
check "$BG" "bg: --no-pager then -C"          'git --no-pager -C /r push --force'          2
check "$BG" "bg: canonical force push"        'git push --force origin feature'            2
check "$BG" "bg: canonical protected push"    'git push origin main'                       2

# --- branch-guard: `+branch` is a force push with no --force in it ---
check "$BG" "bg: +refspec, feature branch"    'git push origin +feature:feature'           2
check "$BG" "bg: +refspec, no colon"          'git push origin +feature'                   2
check "$BG" "bg: -C plus +refspec"            'git -C /repo push origin +feature'          2

# --- branch-guard: still lets ordinary work through ---
check "$BG" "bg: ordinary push"               'git push origin feature'                    0
check "$BG" "bg: -C ordinary push"            'git -C /repo push origin feature'           0
check "$BG" "bg: dry run"                     'git push --dry-run origin feature'          0
check "$BG" "bg: rm -f after the push is not a force push" \
                                              'git push origin feature && rm -f tmp.txt'   0

# --- secret-guard: globals before `add` ---
check "$SG" "sg: -C, .env"                    'git -C /repo add .env'                      2
check "$SG" "sg: -C, private key"             'git -C /repo add id_rsa'                    2
check "$SG" "sg: --git-dir, .env"             'git --git-dir=/r/.git add .env'             2
check "$SG" "sg: canonical .env"              'git add .env'                               2
check "$SG" "sg: ordinary add"                'git add src/main.py'                        0
check "$SG" "sg: -C ordinary add"             'git -C /repo add src/main.py'               0

# --- destructive-guard: globals before the verb ---
check "$DG" "dg: -C, reset --hard"            'git -C /repo reset --hard HEAD~5'           2
check "$DG" "dg: --git-dir, reset --hard"     'git --git-dir=/r/.git reset --hard'         2
check "$DG" "dg: -c, reset --hard"            'git -c user.name=x reset --hard'            2
check "$DG" "dg: -C, clean -fd"               'git -C /repo clean -fd'                     2
check "$DG" "dg: -C, checkout --force"        'git -C /repo checkout --force main'         2
check "$DG" "dg: canonical reset --hard"      'git reset --hard HEAD~1'                    2
check "$DG" "dg: canonical clean"             'git clean -fd'                              2

# --- destructive-guard: the pre-filter still tells mentions from invocations ---
check "$DG" "dg: reset --hard inside a quoted string" \
                                              "echo 'git reset --hard は危険'"             0
check "$DG" "dg: -C read-only"                'git -C /repo log'                           0
check "$DG" "dg: -C dry-run clean"            'git -C /repo clean --dry-run'               0
check "$DG" "dg: reset --soft"                'git reset --soft HEAD~1'                    0
check "$DG" "dg: status"                      'git status'                                 0

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" = 0 ]
