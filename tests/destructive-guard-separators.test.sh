#!/bin/bash
# destructive-guard: command separators
#
# Checks 2, 3 and 7 listed their separators as (^ | ; | && | ||) and left out
# a bare `&`. `true & git reset --hard` therefore ran unguarded — the same
# "allow-list of separators" hole that has bitten this guard before.
# Measured on 2026-07-27: all three checks let a bare & through.
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
        echo "PASS: $desc"; ((PASS++))
    else
        echo "FAIL: $desc (expected exit $want, got $code)"; ((FAIL++))
    fi
}

# Check 2 — git reset --hard, reachable through every separator
check "reset: bare & is blocked"        'true & git reset --hard'    2
check "reset: semicolon is blocked"     'true ; git reset --hard'    2
check "reset: && is blocked"            'true && git reset --hard'   2
check "reset: || is blocked"            'false || git reset --hard'  2
check "reset: start of line is blocked" 'git reset --hard'           2
check "reset: --soft stays allowed"     'git reset --soft HEAD~1'    0

# Check 3 — git clean
check "clean: bare & is blocked"        'true & git clean -fd'       2
check "clean: && is blocked"            'true && git clean -fd'      2
check "clean: start of line is blocked" 'git clean -fd'              2
check "clean: --dry-run stays allowed"  'git clean --dry-run'        0

# Check 7 — git checkout --force
check "checkout: bare & is blocked"     'true & git checkout -f main'  2
check "checkout: && is blocked"         'true && git checkout -f main' 2
check "checkout: plain checkout allowed" 'git checkout main'           0
check "checkout: plain switch allowed"  'git switch feature'           0

# Check 6 — sudo in front of a destructive command.
#
# This check anchored its pattern with `^\s*sudo`, so the anchor was applied to
# the whole command string instead of to each command position. Anything placed
# after a separator was never examined. It stayed invisible for a long time
# because Check 1 independently blocks rm on a sensitive path, so the usual
# probe (`cd /tmp && sudo rm -rf /var`) still came back blocked. The gap only
# shows on the targets Check 6 alone is responsible for: an ordinary relative
# path, and dd/mkfs, which no other check looks at.
# Measured 2026-08-03 against the shipped scripts.json: 7 of 8 such commands
# exited 0 once a separator was placed in front. Same shape as PR #937.
check "sudo rm: start of line is blocked" 'sudo rm -rf myproject'                  2
check "sudo rm: && is blocked"            'cd /tmp && sudo rm -rf myproject'       2
check "sudo rm: semicolon is blocked"     'cd /tmp; sudo rm -rf myproject'         2
check "sudo rm: bare & is blocked"        'true & sudo rm -rf myproject'           2
check "sudo rm: || is blocked"            'false || sudo rm -rf myproject'         2
check "sudo rm -r: && is blocked"         'cd /tmp && sudo rm -r data'             2
check "sudo dd: && is blocked"            'cd /tmp && sudo dd if=/dev/zero of=/dev/sda' 2
check "sudo mkfs: && is blocked"          'cd /tmp && sudo mkfs.ext4 /dev/sdb1'    2
check "sudo chmod 777: && is blocked"     'cd /tmp && sudo chmod -R 777 /opt/app'  2

# Closing the hole must not close anything else. sudo on a harmless command is
# everyday work and stays allowed in every position.
check "sudo apt stays allowed"            'sudo apt update'                        0
check "sudo apt after && stays allowed"   'cd /tmp && sudo apt update'             0
check "sudo -l stays allowed"             'sudo -l'                                0
check "sudo systemctl stays allowed"      'cd /srv && sudo systemctl reload nginx' 0

# Check 7 — PowerShell Remove-Item.
#
# The skip that keeps `echo "Remove-Item -Recurse -Force"` from being read as a
# deletion was anchored the same way, so it only applied when the command
# *began* with a string-output command. Put anything in front and the guard
# blocked a command that only prints text. Measured 2026-08-03: exit 2 on
# `cd /tmp && echo "..."`. That is the over-tightening side of the same anchor.
check "PS: bare Remove-Item is blocked"   'Remove-Item -Recurse -Force *'          2
check "PS: after && is blocked"           'cd /tmp && Remove-Item -Recurse -Force *' 2
check "PS: after semicolon is blocked"    'cd /tmp; Remove-Item -Recurse -Force *' 2
check "PS: powershell wrapper is blocked" 'powershell -c "Remove-Item -Recurse -Force C:\\Users\\john"' 2
check "PS: single file stays allowed"     'Remove-Item ./file.txt'                 0
check "PS: echo of the words allowed"     'echo "Remove-Item -Recurse -Force"'     0
check "PS: echo after && allowed"         'cd /tmp && echo "Remove-Item -Recurse -Force"' 0
check "PS: git commit message allowed"    'git commit -m "handle Remove-Item -Recurse -Force"' 0
check "PS: commit message after && ok"    'cd repo && git commit -m "handle Remove-Item -Recurse -Force"' 0
check "PS: grep for the words allowed"    'cat notes.txt | grep "Remove-Item -Recurse -Force"' 0

# Nothing above should have changed the ordinary allow cases
check "read-only command allowed"       'grep -r TODO .'             0
check "safe dir deletion allowed"       'rm -rf node_modules'        0
check "plain cd compound allowed"       'cd /tmp && ls -la'          0
check "echo compound allowed"           'echo hello && pwd'          0

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
