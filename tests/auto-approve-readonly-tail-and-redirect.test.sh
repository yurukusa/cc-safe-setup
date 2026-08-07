#!/bin/bash
# auto-approve-readonly: a read-only command NAME is not a read-only COMMAND
#
# This hook was one of the three left out of the 2026-08-03 sweep
# (tests/auto-approve-compound-tail.test.sh) because its pipe handling and
# `case` structure were unlike the five that were fixed mechanically. It kept
# the same defect the sweep was about, and it is the only one of the three that
# the paid book names by title — chapter 1 of 6076c23b1cb18b, which is free to
# read, calls it a "quick win" and tells readers to install it.
#
# Measured 2026-08-08 against the shipped copy, all nine of these were approved:
#
#   cat foo.txt && rm -rf /tmp/z
#   find . -name "*.log" -delete
#   find / -name "*.tmp" -exec rm -rf {} \;
#   ls > ~/.bashrc
#   grep -r secret . > /etc/passwd
#   env > /tmp/all-env.txt
#   ps aux | grep x; rm -rf /tmp/z
#   cat /dev/urandom > /dev/sda
#   cat ~/.ssh/id_rsa > /tmp/x
#
# The same run over 14,617 real Bash invocations from this environment's session
# logs: 2,513 approvals before the fix, 390 after. 2,123 of the original
# approvals (84.5%) carried a redirect, a chained command, a substitution, or a
# destructive find option in the part the hook never looked at.
#
# As in the earlier sweep, the fix is not to block. This hook only ever adds
# approvals, so anything it cannot vouch for returns no decision and falls
# through to the normal permission flow.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="examples/auto-approve-readonly.sh"

PASS=0; FAIL=0

check() {
    local desc="$1" cmd="$2" want="$3"   # want: approve | none
    local payload out got
    payload=$(python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
    out=$(printf '%s' "$payload" | bash "$ROOT/$HOOK" 2>/dev/null)
    if printf '%s' "$out" | grep -qE '"allow"|"approve"'; then got=approve; else got=none; fi
    if [ "$got" = "$want" ]; then
        echo "PASS: [auto-approve-readonly] $desc"; PASS=$((PASS+1))
    else
        echo "FAIL: [auto-approve-readonly] $desc (expected $want, got $got)"; FAIL=$((FAIL+1))
    fi
}

# --- the tail the hook never read -------------------------------------------
check "chained destroy after a read"      'cat foo.txt && rm -rf /tmp/z'            none
check "chained destroy after a pipeline"  'ps aux | grep x; rm -rf /tmp/z'          none
check "find with -delete"                 'find . -name "*.log" -delete'            none
check "find with -exec"                   'find / -name "*.tmp" -exec rm -rf {} \;' none
check "redirect over a dotfile"           'ls > /home/u/.bashrc'                    none
check "redirect over a system file"       'grep -r secret . > /etc/passwd'          none
check "redirect of environment"           'env > /tmp/all-env.txt'                  none
check "redirect over a device"            'cat /dev/urandom > /dev/sda'             none
check "credential read into a file"       'cat /home/u/.ssh/id_ed25519 > /tmp/x'    none
check "command substitution in args"      'cat $(find / -name id_rsa)'              none
check "backgrounded tail"                 'ls -la & rm -rf /tmp/z'                  none

# --- control: what the hook exists to approve must stay approved -------------
check "plain ls"                          'ls -la'                                  approve
check "plain git status"                  'git status'                              approve
check "plain grep"                        'grep -n hello file.py'                   approve
check "plain wc"                          'wc -l file.txt'                          approve
check "plain cat"                         'cat README.md'                           approve
check "read-only pipeline"                'cat file.txt | head -20'                 approve

echo
echo "auto-approve-readonly tail/redirect: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
