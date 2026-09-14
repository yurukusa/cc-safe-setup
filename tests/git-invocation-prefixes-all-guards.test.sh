#!/bin/bash
# `git` did not have to be the first word -- in branch-guard and secret-guard too
#
# 2026-09-14, #1121 moved destructive-guard's git checks off the "start of a
# segment" anchor and onto CC_CMDPOS, which also recognises a path, a sudo, an
# environment assignment and the usual wrappers. branch-guard and secret-guard
# have the same gate and were not touched, so the fix covered one guard out of
# three.
#
# Measured the same day, nine invocation forms against each subcommand, feeding
# each guard the same JSON on stdin:
#
#   destructive-guard   9 of 9 blocked   (fixed in #1121)
#   branch-guard        2 of 9 blocked
#   secret-guard        2 of 9 blocked
#
# The seven that walked through were `/usr/bin/git`, `./git`, `sudo git`,
# `env FOO=1 git`, `FOO=1 git`, `time git` and `nohup git`. Each one exited 0,
# which Claude Code reads as "this hook has no objection", not as "this hook did
# not look".
#
# Also here: `git send-pack --force origin main`. send-pack is the plumbing
# spelling of a push, and branch-guard's own header says it blocks force pushes
# on all branches and pushes to protected branches -- but its gate only knew the
# word `push`, so both of those promises were spelled around.
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

# The nine invocation forms. `%s` is where the git command goes.
PREFIXES=(
    '%s'
    '/usr/bin/%s'
    './%s'
    'sudo %s'
    'env FOO=1 %s'
    'FOO=1 %s'
    'time %s'
    'nohup %s'
    'cd /tmp && %s'
)
PREFIX_NAMES=(bare abspath relpath sudo env-assign leading-assign time nohup separator)

# Each guard with a subcommand it owns. All nine forms must be refused.
run_grid() {
    local guard="$1" label="$2" sub="$3"
    local i fmt name cmd
    for i in "${!PREFIXES[@]}"; do
        fmt="${PREFIXES[$i]}"; name="${PREFIX_NAMES[$i]}"
        # shellcheck disable=SC2059
        cmd=$(printf "$fmt" "$sub")
        check "$guard" "$label [$name]" "$cmd" 2
    done
}

run_grid "$DG" "dg: reset --hard"        'git reset --hard HEAD~5'
run_grid "$DG" "dg: clean -fd"           'git clean -fd'
run_grid "$BG" "bg: force push"          'git push --force origin main'
run_grid "$BG" "bg: +main is a force"    'git push origin +main'
run_grid "$BG" "bg: -uf short cluster"   'git push -uf origin feature'
run_grid "$SG" "sg: stage .env"          'git add .env'

# --- send-pack: the plumbing spelling of a push ---
check "$BG" "bg: send-pack --force"           'git send-pack --force origin main'          2
check "$BG" "bg: send-pack --force with -C"   'git -C /repo send-pack --force origin main' 2
check "$BG" "bg: send-pack to main"           'git send-pack origin main'                  2
check "$BG" "bg: send-pack to a feature"      'git send-pack origin feature'               0

# --- the approve side: widening the gate must not start refusing ordinary work ---
check "$BG" "bg: ordinary push to a feature"  'git push origin feature'                    0
check "$BG" "bg: -u to a feature"             'git push -u origin feature'                 0
check "$SG" "sg: staging a normal file"       'git add README.md'                          0
check "$SG" "sg: staging a source file"       'git add src/config.ts'                      0
check "$DG" "dg: a dry run is not a delete"   'git clean -nd'                              0

# CC_CMDPOS accepts a path in front of git. It must still require the word to be
# `git` and not merely to start with it.
check "$BG" "bg: gitk is not git"             '/usr/bin/gitk push --force origin main'     0
check "$DG" "dg: a lookalike binary"          './gitfoo reset --hard HEAD~5'               0

# Mentions are not invocations. A space in front of `git` is not a segment break,
# so quoting or grepping for the command must stay allowed.
check "$BG" "bg: the command inside a string" 'echo "run git push --force if you must"'    0
check "$DG" "dg: searching for the command"   "grep -rn 'git reset --hard' ."              0

# ...but the wrappers that really do run it are invocations.
check "$BG" "bg: xargs runs it"               'echo main | xargs git push --force origin'  2

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
