#!/bin/bash
# destructive-guard: mass deletion driven by find
#
# The old Check 5 matched only `find /`, `find ~` and `find ..` followed by
# -delete. The two forms people actually run -- `find . -delete` and
# `find . -exec rm -rf {} \;` -- walked straight past it, and so did every
# variant that quoted the flag or put a wrapper in front of the command.
# Two adversarial reviews in 2026-07 rejected earlier attempts because a
# simpler bypass always survived the word-boundary checks.
#
# The rewrite inverts the detection: normalise the line first (drop quotes,
# drop wrappers, resolve /usr/bin/find, join continuations), then ask three
# plain questions -- is the command find, does it delete, and how wide is the
# search. Everyday narrowed cleanup stays allowed; an unnarrowed sweep does not.
#
# Measured 2026-07-27: 26 of the 30 blocking cases below returned exit 0
# against the shipped guard.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD=$(mktemp); trap 'rm -f "$GUARD"' EXIT
python3 -c "
import json,sys
sys.stdout.write(json.load(open('$ROOT/scripts.json'))['destructive-guard'])" > "$GUARD"

PASS=0; FAIL=0

check() {
    local desc="$1" cmd="$2" want="$3"   # want: 2 = blocked, 0 = allowed
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

# --- the two forms people actually run ---------------------------------------
check "plain find -delete"              'find . -delete'                    2
check "find -exec rm"                   'find . -exec rm -rf {} \;'         2
check "find -execdir rm"                'find . -execdir rm -f {} \;'       2
check "find -exec unlink"               'find . -exec unlink {} \;'         2
check "no root given"                   'find -delete'                      2

# --- N series: quoting defeated the word boundaries --------------------------
check "quoted flag, single"              "find . '-delete'"                 2
check "quoted flag, double"              'find . "-delete"'                 2
check "quoted rm inside -exec"           "find . -exec 'rm' -rf {} \;"      2

# --- K series: a wrapper in front of the real command ------------------------
check "env wrapper"                     'env find . -delete'                2
check "nice wrapper"                    'nice find . -delete'               2
check "nice with option"                'nice -n 5 find . -delete'          2
check "timeout wrapper"                 'timeout 30 find . -delete'         2
check "sudo wrapper"                    'sudo find . -delete'               2
check "exec wrapper"                    'exec find . -delete'               2
check "doubled command builtin"         'command command find . -delete'    2
check "relative path to find"           './find . -delete'                  2
check "absolute path to find"           '/usr/bin/find . -delete'           2
check "leading assignment"              'FOO=1 find . -delete'              2
check "shell -c wrapper"                'bash -c "find . -delete"'          2
check "xargs in front"                  'xargs find . -delete'              2

# --- dangerous search roots ---------------------------------------------------
check "root is /"                       "find / -name '*.log' -delete"      2
check "root is ~"                       "find ~ -name '*.tmp' -delete"      2
check "root is \$HOME"                  'find $HOME -delete'                2
check "root is parent"                  'find .. -delete'                   2

# --- narrowing that does not actually narrow ---------------------------------
check "-type alone is not narrowing"    'find . -type f -delete'            2
check "bare wildcard is not narrowing"  "find . -name '*' -delete"          2
check "-o rebinds the delete"           "find . -name '*.pyc' -o -delete"   2

# --- reachable through any separator, and across a continued line ------------
check "bare & separator"                'true & find . -delete'             2
check "semicolon separator"             'true ; find . -delete'             2
check "line continuation"               'find . \
  -delete'                                                                  2

# --- everyday cleanup must stay allowed --------------------------------------
check "narrowed by name"                "find . -name '*.pyc' -delete"      0
check "narrowed by name and age"        "find ./logs -name '*.log' -mtime +30 -delete" 0
check "type plus name"                  "find . -type f -name '*.tmp' -delete" 0
check "narrowed by -newer"              'find . -newer package.json -delete' 0
check "throwaway dir: node_modules"     'find node_modules -delete'         0
check "throwaway dir: dist"             'find dist -delete'                 0
check "throwaway dir: ./build"          'find ./build -delete'              0
check "print only"                      'find . -print'                     0
check "print only from /"               "find / -name '*.log' -print"       0
check "piped to grep"                   "find . -name '*.py' | xargs grep foo" 0
check "find inside a string"            'echo "find . -delete"'             0
check "find inside a commit message"    'git commit -m "add find . -delete example"' 0
check "prune, no deletion"              'find . -type d -name node_modules -prune' 0
check "unrelated command"               'ls -la'                            0

# --- Check 1: trailing content used to defeat the tilde/HOME position --------
check "bare tilde"                      'rm -rf ~'                          2
check "tilde then a comment"            'rm -rf ~ # cleanup'                2
check "tilde then another argument"     'rm -rf ~ /srv/data'                2
check "quoted HOME"                     'rm -rf "$HOME"'                    2
check "HOME then a redirect"            'rm -rf "$HOME" 2>/dev/null'        2
check "parent then a comment"           'rm -rf .. # oops'                  2
check "cwd then a comment"              'rm -rf . # oops'                   2
check "specific subdirectory allowed"   'rm -rf ./node_modules'             0
check "nested build path allowed"       'rm -rf ./dist/assets'              0
check "path under .git allowed"         'rm -rf .git/objects/tmp'           0

echo
echo "destructive-guard-find-deletion: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
