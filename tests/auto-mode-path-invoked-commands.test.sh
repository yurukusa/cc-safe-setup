#!/bin/bash
# auto-mode-safety-enforcer: the gate counted a path, the checks did not
#
# The gate near the top of the hook decides whether anything below runs. It
# already treats `/usr/bin/rm`, `sudo rm`, `FOO=1 rm`, `time rm` and the rest as
# invocations. The two checks it feeds anchored on a separator or a bare space:
#
#   grep -qE '(^|\s|;|&&|\|)(sudo\s+)?rm\s'
#   grep -qE '(^|\s)(sudo\s+)?(dd\s+.*of=/dev|mkfs\.|fdisk\s|parted\s)'
#
# Nothing in either matches the `rm` in `/usr/bin/rm -rf /`, because the
# character in front of it is `/`. So the call passed the gate and then matched
# no check, and the hook exited 0 -- an affirmative approval.
#
# Measured 2026-09-14: nine invocation forms against six destructive commands,
# twelve of fifty-four cells allowed. All twelve were reached through a path
# (`/usr/bin/...` and `./...`); the sudo, env, assignment, time, nohup and
# separator forms were already covered by the bare-space branch.
#
# The fix widens the anchor to a superset of what was there. It has to be a
# superset: the gate lets `echo "rm -rf /" | sh` through on its pipe-into-a-shell
# arm, and the loose bare-space match is the only thing that stops it after that.
# Replacing the anchor with command-position-only reopened four cases in
# tests/auto-mode-quoted-targets.test.sh.
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/auto-mode-safety-enforcer.sh"

PASS=0; FAIL=0

check() {
    local desc="$1" cmd="$2" want="$3"   # want: 2 = blocked, 0 = allowed
    local payload code
    payload=$(python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
    printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
    code=$?
    if [ "$code" = "$want" ]; then
        echo "PASS: $desc"; PASS=$((PASS+1))
    else
        echo "FAIL: $desc (expected exit $want, got $code)"; FAIL=$((FAIL+1))
    fi
}

PREFIXES=(
    '%s'
    '/usr/bin/%s'
    './%s'
    '/bin/%s'
    'sudo %s'
    'env FOO=1 %s'
    'FOO=1 %s'
    'time %s'
    'nohup %s'
    'cd /tmp && %s'
)
PREFIX_NAMES=(bare abspath relpath binpath sudo env-assign leading-assign time nohup separator)

DESTRUCTIVE=(
    'rm -rf /'
    'rm -rf /etc'
    'rm -rf ~'
    'dd if=/dev/zero of=/dev/sda'
    'mkfs.ext4 /dev/sda1'
    'fdisk /dev/sda'
)

for sub in "${DESTRUCTIVE[@]}"; do
    for i in "${!PREFIXES[@]}"; do
        # shellcheck disable=SC2059
        cmd=$(printf "${PREFIXES[$i]}" "$sub")
        check "$sub [${PREFIX_NAMES[$i]}]" "$cmd" 2
    done
done

# --- the approve side: a wider anchor must not start refusing ordinary work ---
check "a local build directory"        'rm -rf node_modules'              0
check "a single object file"           'rm -f build/tmp.o'                0
check "listing a system directory"     'ls -la /etc'                      0
check "searching for the command"      "grep -rn 'rm -rf /' docs/"        0
check "copying an image file"          'dd if=in.img of=out.img'          0
check "a lookalike binary"             '/usr/bin/rmdirs -rf /'            0
check "a word that starts with rm"     'rmate /etc/hosts'                 0

# --- the case the loose branch is there for ---
check "a quoted command piped to sh"   'echo "rm -rf /" | sh'             2

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
