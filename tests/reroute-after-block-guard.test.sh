#!/bin/bash
# Tests for reroute-after-block-guard.sh
# Run: bash tests/reroute-after-block-guard.test.sh
set -uo pipefail

PASS=0
FAIL=0
HOOK="$(dirname "$0")/../examples/reroute-after-block-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a transcript with a previous (tool_use + tool_result) pair, then check
# the hook against a current action. $1=blocked target, $2=is_error,
# $3=result text, $4=tool name for blocked action.
make_transcript() {
    local blocked="$1" err="$2" text="$3" tn="${4:-Bash}" f
    f="$TMP/t_$RANDOM.jsonl"
    local inkey="command"
    [ "$tn" != "Bash" ] && inkey="file_path"
    jq -nc --arg b "$blocked" --arg k "$inkey" --arg tn "$tn" \
        '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_x",name:$tn,input:{($k):$b}}]}}' >"$f"
    jq -nc --arg e "$err" --arg t "$text" \
        '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_x",is_error:($e=="true"),content:$t}]}}' >>"$f"
    printf '%s' "$f"
}

# $1=transcript path, $2=current command/file, $3=tool name -> input JSON
make_input() {
    local tp="$1" cur="$2" tn="${3:-Bash}" k="command"
    [ "$tn" != "Bash" ] && k="file_path"
    jq -nc --arg tp "$tp" --arg c "$cur" --arg k "$k" --arg tn "$tn" \
        '{transcript_path:$tp, tool_name:$tn, tool_input:{($k):$c}}'
}

run() {
    local input="$1" expected="$2" desc="$3" env="${4:-}" actual=0
    if [ -n "$env" ]; then
        echo "$input" | env $env bash "$HOOK" >/dev/null 2>/dev/null || actual=$?
    else
        echo "$input" | bash "$HOOK" >/dev/null 2>/dev/null || actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected $expected, got $actual)"; FAIL=$((FAIL + 1))
    fi
}

echo "reroute-after-block-guard.sh tests"
echo ""

HOOKERR='PreToolUse:Bash hook error: [bash /home/u/.claude/hooks/block-push.sh]: blocked push'

# 1. Block fired on a path, current reroutes toward the same path -> stop.
t=$(make_transcript "git push origin main:src/app.py" "true" "$HOOKERR")
run "$(make_input "$t" "git -C . push --force origin main && cat src/app.py")" 2 "reroute toward same path after block -> exit 2"

# 2. Same block, but current targets an unrelated path -> allow.
t=$(make_transcript "git push origin main:src/app.py" "true" "$HOOKERR")
run "$(make_input "$t" "ls docs/readme.md")" 0 "different target after block -> exit 0"

# 3. Previous tool SUCCEEDED (no gate fired) -> allow even if same path.
t=$(make_transcript "cat src/app.py" "false" "file contents here")
run "$(make_input "$t" "rm src/app.py")" 0 "previous succeeded, no gate -> exit 0"

# 4. Error present but NOT a gate block (generic failure) -> allow.
t=$(make_transcript "cat src/app.py" "true" "cat: src/app.py: No such file or directory")
run "$(make_input "$t" "vi src/app.py")" 0 "non-gate error -> exit 0"

# 5. Edit reroute toward the same file that was just blocked -> stop.
t=$(make_transcript "/home/u/proj/secret.env" "true" "PreToolUse:Edit hook error: [bash /x/dotenv-guard.sh]: blocked" "Edit")
run "$(make_input "$t" "/home/u/proj/secret.env" "Write")" 2 "Write reroute to just-blocked file -> exit 2"

# 6. One-shot override -> allow.
t=$(make_transcript "git push origin main:src/app.py" "true" "$HOOKERR")
run "$(make_input "$t" "git push --force origin main:src/app.py")" 0 "CC_REROUTE_ALLOW=1 override -> exit 0" "CC_REROUTE_ALLOW=1"

# 7. Disabled -> allow.
t=$(make_transcript "git push origin main:src/app.py" "true" "$HOOKERR")
run "$(make_input "$t" "git push origin main:src/app.py")" 0 "CC_REROUTE_DISABLE=1 -> exit 0" "CC_REROUTE_DISABLE=1"

# 8. No transcript_path -> allow (fail open).
run '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' 0 "no transcript_path -> exit 0"

# 9. Generic "permission denied" is NOT a Claude Code gate -> allow (fail open).
t=$(make_transcript "rm /etc/hosts" "true" "rm: cannot remove '/etc/hosts': Permission denied")
run "$(make_input "$t" "sudo rm /etc/hosts")" 0 "generic permission denied is not a gate -> exit 0"

# 10. Block on a path but current shares only a trivial flag/word -> allow.
t=$(make_transcript "git push origin main" "true" "$HOOKERR")
run "$(make_input "$t" "git status")" 0 "no shared concrete path token -> exit 0"

# 11. Server-side git rejection ("blocked by required reviews") is NOT a gate -> allow.
t=$(make_transcript "git push origin main" "true" "remote: error: GH006: Protected branch update failed; blocked by required reviews")
run "$(make_input "$t" "git push --force origin main")" 0 "branch-protection rejection is not a gate -> exit 0"

# 12. After a real hook block, inspecting the rejected branch (a git ref, not a
#     file) must stay allowed — git refs are not concrete targets.
t=$(make_transcript "git push origin/main" "true" "$HOOKERR")
run "$(make_input "$t" "git log origin/main --oneline")" 0 "git ref (origin/main) is not a target -> exit 0"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
