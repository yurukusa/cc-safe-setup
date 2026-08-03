#!/bin/bash
# destructive-guard: `rm -rf *`
#
# Found by measuring all three channels this project actually ships through, with
# the same 27 destructive forms:
#
#   the itch.io kit (as downloaded from the store)   15 of 27 walked through
#   npm 29.8.0 (2026-04-20)                          10 of 27
#   this tree                                         7 of 27
#
# `rm -rf *` was in all three lists. Check 1 asks whether the target begins with
# `/`, `~`, `$HOME` and so on, and a glob begins with none of them.
#
# `*` expands to everything in the current directory, so `rm -rf *` is `rm -rf .`
# under another name — and `rm -rf .` has been blocked for months. Blocking one
# and not the other does not hold together.
#
# The check is deliberately narrow: only a bare `*` or `./*` standing as the whole
# target. `rm -rf *.log`, `rm -rf build/*` and `rm -rf node_modules/*` are named
# targets and stay allowed. Stopping the ordinary cleanup is its own kind of
# broken, and a guard that cries wolf gets removed.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD=$(mktemp); trap 'rm -f "$GUARD"' EXIT
python3 -c "
import json,sys
sys.stdout.write(json.load(open('$ROOT/scripts.json'))['destructive-guard'])" > "$GUARD"

PASS=0; FAIL=0

check() {
    local desc="$1" cmd="$2" want="$3"
    local payload code
    payload=$(python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
    printf '%s' "$payload" | bash "$GUARD" >/dev/null 2>&1
    code=$?
    if [ "$code" = "$want" ]; then
        echo "PASS: $desc"; PASS=$((PASS+1))
    else
        echo "FAIL: $desc (expected exit $want, got $code)"; FAIL=$((FAIL+1))
    fi
}

# the bare glob, in the forms people actually type
check "bare glob"                     'rm -rf *'                     2
check "dot-slash glob"                'rm -rf ./*'                   2
check "flags the other way round"     'rm -fr *'                     2
check "split flags"                   'rm -r -f *'                   2
check "long flags"                    'rm --recursive --force *'     2
check "quoted glob"                   "rm -rf '*'"                   2
check "double-quoted glob"            'rm -rf "*"'                   2
check "behind sudo"                   'sudo rm -rf *'                2
check "after a separator"             'echo start && rm -rf *'       2
check "after a semicolon"             'cd /tmp ; rm -rf *'           2

# named targets stay allowed — this is the half that keeps the guard usable
check "extension glob"                'rm -rf *.log'                 0
check "glob under a directory"        'rm -rf build/*'               0
check "glob under node_modules"       'rm -rf node_modules/*'        0
check "plain directory"               'rm -rf node_modules'          0
check "relative directory"            'rm -rf ./build'               0
check "dist"                          'rm -rf dist'                  0
check "prefix glob"                   'rm -rf tmp*'                  0
check "glob deeper in a path"         'rm -rf src/*.tmp'             0

# a glob outside rm is nobody's business here
check "ls with a glob"                'ls *'                         0
check "echo with a glob"              'echo *'                       0
check "git add with a glob"           'git add *'                    0

echo
echo "destructive-guard-bare-glob: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
