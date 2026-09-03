#!/bin/bash
# A trailing backslash split every guard's view of the command in two
#
# The shell joins `\` + newline before it runs anything, so
#
#   rm -rf \
#     ~/Documents
#
# is one deletion. grep is line-oriented: it saw `rm -rf \` on one line and
# `~/Documents` on the next, matched neither against a pattern that wants the
# flag and the path together, and the hook exited 0 -- an approval.
#
# This is not an exploit shape. 416 of 43,858 real Bash calls in this operator's
# own transcripts (0.9%) use a line continuation; 28 of those are git commands.
# It is how people and agents write long commands.
#
# Measured 2026-09-03 against the shipped copies, after #1107:
#   destructive-guard  rm -rf \ + ~/Documents        exit 0
#                      chmod -R \ + 777 /            exit 0
#                      git reset \ + --hard          exit 0
#   branch-guard       git push \ + --force feature  exit 0
#   secret-guard       git add \ + .env              exit 0
#
# `rm -rf \` + `/` and `sudo \` + `rm -rf /var` did block, but for the wrong
# reason -- a different check happened to match one of the two halves. Blocking
# by accident is not coverage, and it does not survive a change of branch name
# or path: `git push \` + `--force origin main` was refused only because `main`
# is a protected branch, and the same command aimed at a feature branch went
# through.
#
# The fix joins the continuations once, where COMMAND is read, so every check --
# git and non-git alike -- sees the command the shell will actually run.
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

# --- destructive-guard: the non-git checks were affected too ---
check "$DG" "dg: rm split across a continuation, root"  'rm -rf \
  /'                                                                             2
check "$DG" "dg: rm split across a continuation, home"  'rm \
  -rf ~/Documents'                                                               2
check "$DG" "dg: chmod 777 split"                       'chmod -R \
  777 /'                                                                         2
check "$DG" "dg: sudo split from its command"           'sudo \
  rm -rf /var'                                                                   2
check "$DG" "dg: reset --hard split"                    'git reset \
  --hard HEAD~1'                                                                 2
check "$DG" "dg: continuation and -C together"          'git \
  -C /repo reset --hard'                                                         2

# --- branch-guard ---
check "$BG" "bg: force push split, feature branch"      'git push \
  --force origin feature'                                                        2
check "$BG" "bg: force push split, protected branch"    'git push \
  --force origin main'                                                           2
check "$BG" "bg: continuation and -C together"          'git \
  -C /r push --force'                                                            2

# --- secret-guard ---
check "$SG" "sg: add .env split"                        'git add \
  .env'                                                                          2
check "$SG" "sg: add private key split"                 'git add \
  id_rsa'                                                                        2

# --- nothing that used to block stopped blocking ---
check "$DG" "dg: canonical rm on root"                  'rm -rf /'               2
check "$DG" "dg: canonical rm on home"                  'rm -rf ~/Documents'     2
check "$DG" "dg: canonical reset --hard"                'git reset --hard HEAD~1' 2
check "$DG" "dg: -C clean"                              'git -C /repo clean -fd' 2
check "$BG" "bg: canonical force push"                  'git push --force origin feature' 2
check "$BG" "bg: +refspec"                              'git push origin +feature' 2
check "$SG" "sg: canonical .env"                        'git add .env'           2

# --- and nothing ordinary started blocking ---
check "$DG" "dg: status"                                'git status'             0
check "$DG" "dg: -C log"                                'git -C /repo log'       0
check "$DG" "dg: mention inside a quoted string"        "echo 'git reset --hard は危険'" 0
check "$DG" "dg: ls across a continuation"              'ls -la \
  /tmp'                                                                          0
check "$DG" "dg: grep across a continuation"            'grep -r foo \
  ./src'                                                                         0
check "$BG" "bg: ordinary push"                         'git push origin feature' 0
check "$BG" "bg: dry run across a continuation"         'git push \
  --dry-run origin feature'                                                      0
check "$SG" "sg: ordinary add"                          'git add src/main.py'    0
check "$SG" "sg: ordinary add across a continuation"    'git add \
  src/main.py'                                                                   0

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" = 0 ]
