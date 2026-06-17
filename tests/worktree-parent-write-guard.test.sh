#!/bin/bash
# Test for worktree-parent-write-guard.sh
#
# Verifies the hook blocks (exit 2) writes that target the PARENT repo while
# the agent is working in a worktree nested at <repo>/.claude/worktrees/<name>/,
# and allows (exit 0) correct in-worktree writes and writes that are not part of
# the nested-worktree danger (normal repos, /tmp, home configs).
#
# Customer evidence: anthropics/claude-code #62547, #60679, #69026.

set -u

HOOK="$(dirname "$0")/../examples/worktree-parent-write-guard.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

PASS=0
FAIL=0

run_case() {
    local name="$1" cwd="$2" target="$3" expect="$4"
    local input rc
    input=$(jq -nc --arg cwd "$cwd" --arg t "$target" '{cwd:$cwd, tool_input:{file_path:$t}}')
    echo "$input" | "$HOOK" >/dev/null 2>&1
    rc=$?
    if [ "$expect" = "block" ]; then
        if [ "$rc" = "2" ]; then PASS=$((PASS+1)); echo "PASS: $name"
        else FAIL=$((FAIL+1)); echo "FAIL: $name (expected block/2, got $rc)"; fi
    else
        if [ "$rc" = "0" ]; then PASS=$((PASS+1)); echo "PASS: $name"
        else FAIL=$((FAIL+1)); echo "FAIL: $name (expected allow/0, got $rc)"; fi
    fi
}

W="/home/u/app/.claude/worktrees/foo"

# --- dangerous: must block ---
run_case "parent canonical src"      "$W"     "/home/u/app/src/x.js"                     block
run_case "parent root file"          "$W"     "/home/u/app/README.md"                    block
run_case "subdir cwd -> parent"      "$W/src" "/home/u/app/src/x.js"                      block
run_case "sibling worktree target"   "$W"     "/home/u/app/.claude/worktrees/bar/x.js"   block

# --- safe: must allow ---
run_case "correct in-worktree (abs)" "$W"     "$W/src/x.js"                              allow
run_case "in-worktree subdir cwd"    "$W/src" "$W/src/x.js"                              allow
run_case "normal repo (no worktree)" "/home/u/app" "/home/u/app/src/x.js"               allow
run_case "write to /tmp"             "$W"     "/tmp/scratch.txt"                         allow
run_case "write to home config"      "$W"     "/home/u/.claude/settings.json"           allow

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
