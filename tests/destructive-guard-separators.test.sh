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

# Nothing above should have changed the ordinary allow cases
check "read-only command allowed"       'grep -r TODO .'             0
check "safe dir deletion allowed"       'rm -rf node_modules'        0

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
