#!/bin/bash
# Core scripts: the payload reader must not depend on jq alone
#
# Every core hook in scripts.json read its input with `jq -r ... 2>/dev/null`
# and then did `[ -z "$VAR" ] && exit 0`. On a machine without jq that reads as
# "there was nothing to inspect" rather than "there was nothing to inspect it
# with": the hook exits 0, prints nothing, and protects nothing. It is still
# listed in settings.json, so nothing looks wrong.
#
# Measured on 2026-07-27 against the shipped core: with jq removed from PATH,
# `rm -rf` on a system path and `git reset --hard` both returned exit 0 in
# complete silence.
#
# The fix is a reader chain (jq -> python3 -> node) plus a single warning when
# none of the three exist. We do NOT block in that case: refusing every Bash
# call would leave Claude Code unusable, and stopping all work is a failure,
# not safety. The same decision was shipped for the marketplace plugins.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; SKIP=0

# --- build PATHs that expose only some of the three readers -------------------
mk_env() {
    local label="$1"; shift
    local dir="$WORK/bin-$label"
    mkdir -p "$dir"
    local t p
    for t in bash sh grep sed cat date mkdir tr cut awk env dirname basename \
             head tail wc sort uniq touch rm find printf; do
        p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$dir/$t"
    done
    for t in "$@"; do
        p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$dir/$t"
    done
    echo "$dir"
}

ENV_PY=$(mk_env python python3)
ENV_NODE=$(mk_env node node)
ENV_NONE=$(mk_env none)

extract() {
    python3 -c "
import json,sys
sys.stdout.write(json.load(open('$ROOT/scripts.json'))['$1'])" > "$WORK/$1.sh"
}

payload() {
    python3 -c '
import json,sys
print(json.dumps(json.loads(sys.argv[1])))' "$1"
}

# run a hook under a restricted PATH; echoes "<exit>|<stderr>"
run_under() {
    local dir="$1" script="$2" data="$3" out code
    out=$(printf '%s' "$data" | PATH="$dir" bash "$WORK/$script.sh" 2>&1 >/dev/null)
    code=$?
    printf '%s|%s' "$code" "$out"
}

check_blocks() {
    local script="$1" data="$2" dir="$3" label="$4" runtime="$5"
    if [ ! -e "$dir/$runtime" ]; then
        echo "SKIP: $script blocks under $label ($runtime not installed here)"; SKIP=$((SKIP+1)); return
    fi
    local r code
    r=$(run_under "$dir" "$script" "$data"); code=${r%%|*}
    if [ "$code" = "2" ]; then
        echo "PASS: $script still blocks with only $label"; PASS=$((PASS+1))
    else
        echo "FAIL: $script did not block with only $label (exit $code)"; FAIL=$((FAIL+1))
    fi
}

check_warns() {
    local script="$1" data="$2"
    local r code err
    r=$(run_under "$ENV_NONE" "$script" "$data"); code=${r%%|*}; err=${r#*|}
    if [ "$code" != "0" ]; then
        echo "FAIL: $script should allow when no reader exists (exit $code)"; FAIL=$((FAIL+1))
    elif printf '%s' "$err" | grep -q 'WARNING'; then
        echo "PASS: $script warns instead of failing silently"; PASS=$((PASS+1))
    else
        echo "FAIL: $script exits 0 in silence when no reader exists"; FAIL=$((FAIL+1))
    fi
}

check_allows() {
    local script="$1" data="$2" dir="$3" label="$4"
    local r code
    r=$(run_under "$dir" "$script" "$data"); code=${r%%|*}
    if [ "$code" = "0" ]; then
        echo "PASS: $script leaves a harmless command alone under $label"; PASS=$((PASS+1))
    else
        echo "FAIL: $script blocked a harmless command under $label (exit $code)"; FAIL=$((FAIL+1))
    fi
}

DANGER_RM=$(payload '{"tool_name":"Bash","tool_input":{"command":"rm -rf /etc"}}')
DANGER_RESET=$(payload '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}')
DANGER_ENV=$(payload '{"tool_name":"Bash","tool_input":{"command":"git add .env"}}')
DANGER_FORCE=$(payload '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}')
DANGER_CLEAR=$(payload '{"prompt":"/clear"}')
SAFE_LS=$(payload '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')
SAFE_ADD=$(payload '{"tool_name":"Bash","tool_input":{"command":"git add README.md"}}')

for s in destructive-guard secret-guard branch-guard clear-command-confirm-guard \
         cd-git-allow comment-strip api-error-alert subagent-context-size-guard; do
    extract "$s"
done

check_blocks destructive-guard "$DANGER_RM"    "$ENV_PY"   "python3" python3
check_blocks destructive-guard "$DANGER_RM"    "$ENV_NODE" "node"    node
check_blocks destructive-guard "$DANGER_RESET" "$ENV_PY"   "python3" python3
check_blocks destructive-guard "$DANGER_RESET" "$ENV_NODE" "node"    node
check_blocks secret-guard      "$DANGER_ENV"   "$ENV_PY"   "python3" python3
check_blocks secret-guard      "$DANGER_ENV"   "$ENV_NODE" "node"    node
check_blocks branch-guard      "$DANGER_FORCE" "$ENV_PY"   "python3" python3
check_blocks branch-guard      "$DANGER_FORCE" "$ENV_NODE" "node"    node
check_blocks clear-command-confirm-guard "$DANGER_CLEAR" "$ENV_PY" "python3" python3

check_warns destructive-guard "$DANGER_RM"
check_warns secret-guard      "$DANGER_ENV"
check_warns branch-guard      "$DANGER_FORCE"
check_warns cd-git-allow      "$SAFE_LS"
check_warns comment-strip     "$SAFE_LS"
check_warns api-error-alert   "$(payload '{"stop_reason":"error","hook_event_name":"Stop"}')"
check_warns subagent-context-size-guard "$(payload '{"tool_input":{"prompt":"fix"}}')"
check_warns clear-command-confirm-guard "$DANGER_CLEAR"

check_allows destructive-guard "$SAFE_LS"  "$ENV_PY"   "python3"
check_allows destructive-guard "$SAFE_LS"  "$ENV_NODE" "node"
check_allows secret-guard      "$SAFE_ADD" "$ENV_PY"   "python3"
check_allows destructive-guard "$SAFE_LS"  "$ENV_NONE" "no reader"

echo
echo "core-scripts-parser-fallback: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
