#!/bin/bash
# destructive-guard: the words do not have to be in that order
#
# Checks 2, 3 and 4 each pinned the position of a flag:
#
#   Check 2  git\s+reset\s+--hard              -- --hard must follow `reset`
#   Check 3  git\s+clean\s+-[a-z]*[fd]         -- the flags must be one bundle, first
#   Check 4  chmod\s+(-R\s+)?777\s+(/|~|\.)    -- -R before 777, path right after
#
# A shell does not care. `git reset HEAD~1 --hard` discards exactly the same work,
# `git clean -x -f -d` deletes more than `git clean -fd`, and `chmod 777 -R /etc`
# is `chmod -R 777 /etc`. All three walked past the guard.
#
# Measured 2026-08-03 against the shipped copy, with the denominator restricted to
# the pairs this guard actually blocks in their canonical form: 5 of 19 reorderings
# were not blocked. After the fix: 0 of 19, with 0 newly blocked out of 28 everyday
# commands.
#
# This is the same shape as the defect in the approving hooks fixed the same day
# (#937/#940/#941/#942/#943/#947/#948), one level up: there the rule assumed the
# dangerous part came *after* the first command position; here it assumes the
# dangerous flag comes in a fixed *slot*. Both are a pattern that encodes a habit
# of typing rather than what the command does.
#
# `[^;&|]` keeps every scan inside one command, so a later command's words are
# never borrowed to make a match.
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

# --- Check 2: git reset --hard, wherever the flag sits ---
check "reset: canonical order"            'git reset --hard HEAD~1'        2
check "reset: flag last"                  'git reset HEAD~1 --hard'        2
check "reset: flag last, named remote"    'git reset origin/main --hard'   2
check "reset: bare"                       'git reset --hard'               2
check "reset: --soft is not --hard"       'git reset --soft HEAD~1'        0
check "reset: plain reset unstages only"  'git reset HEAD~1'               0
check "reset: --hard belongs to the next command" 'git reset HEAD~1 ; echo --hard' 0
check "reset: inside a message"           "git commit -m 'git reset --hard の話'" 0

# --- Check 3: git clean, flags split or reordered ---
check "clean: canonical bundle"           'git clean -fd'                  2
check "clean: split flags"                'git clean -f -d'                2
check "clean: reversed"                   'git clean -d -f'                2
check "clean: another flag first"         'git clean -x -f -d'             2
check "clean: bundle with a trailing x"   'git clean -fdx'                 2
check "clean: bundle with two extras"     'git clean -fdxq'                2
check "clean: long form"                  'git clean --force -d'           2
check "clean: dry run stays allowed"      'git clean -n'                   0
check "clean: dry run with -d"            'git clean -nd'                  0
check "clean: dry run with -d and -x"     'git clean -ndx'                 0
check "clean: long dry run"               'git clean --dry-run'            0
check "clean: force plus dry run is a dry run" 'git clean --force --dry-run' 0

# --- Check 4: chmod 777, wherever -R sits ---
check "chmod: canonical order"            'chmod -R 777 /etc'              2
check "chmod: -R after the mode"          'chmod 777 -R /etc'              2
check "chmod: -R last"                    'chmod 777 /etc -R'              2
check "chmod: long recursive flag"        'chmod --recursive 777 /etc'     2
check "chmod: no -R at all"               'chmod 777 /etc'                 2
check "chmod: home directory"             'chmod 777 -R ~/'                2
check "chmod: relative path"              'chmod 777 -R ./'                2
check "chmod: a narrower mode is fine"    'chmod 644 ./file.txt'           0
check "chmod: 755 on a script"            'chmod 755 ./bin/run'            0
check "chmod: +x is fine"                 'chmod +x script.sh'             0
check "chmod: 777 on a plain filename"    'chmod 777 file.txt'             0

# --- the scans must not cross into the next command ---
check "no borrowing across ;"             'echo 777 ; chmod 644 ./x'       0
check "no borrowing across &&"            'git clean -n && echo -fd'       0

# --- Check 5: a wrapper may carry assignments of its own ---
# Found while judging the 2026-07-27 find hypothesis: the prefix stripper dropped
# leading VAR=value once, then dropped wrappers in a loop. `env LC_ALL=C find` puts
# the assignment *after* the wrapper, so it survived and the command word was read
# as `LC_ALL=C`. Same shape as the rest of this file: a rule that assumed which
# order the pieces arrive in. Assignments are now dropped inside the same loop.
check "find: bare wrapper"                'env find . -delete'             2
check "find: wrapper with an assignment"  'env LC_ALL=C find . -delete'    2
check "find: two assignments"             'env LC_ALL=C TZ=UTC find . -delete' 2
check "find: assignment with no wrapper"  'LC_ALL=C find . -delete'        2
check "find: narrowed cleanup still runs" "find . -name '*.pyc' -delete"   0
check "find: narrowed with a wrapper"     "env LC_ALL=C find . -name '*.pyc' -delete" 0

echo
echo "destructive-guard-flag-order: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
