#!/bin/bash
# Test for worktree-escape-write-guard.sh
#
# Verifies the hook blocks (exit 2) Edit/Write/MultiEdit whose absolute
# file_path escapes the active worktree onto the main checkout
# (Claude Code issue #70069), while letting through:
#   - in-worktree absolute paths
#   - relative paths (resolve against cwd = the worktree)
#   - sessions not in a worktree
#   - paths entirely outside the repo (other guards' concern)
#   - non-edit tools

set -u

HOOK="$(dirname "$0")/../examples/worktree-escape-write-guard.sh"
[ ! -x "$HOOK" ] && chmod +x "$HOOK"

REPO="/home/dev/myrepo"
WT="$REPO/.claude/worktrees/feature-x"

PASS=0
FAIL=0

run_case() {
    local name="$1" tool="$2" cwd="$3" file="$4" expect="$5"
    local input rc
    input=$(jq -nc --arg t "$tool" --arg c "$cwd" --arg f "$file" \
        '{tool_name:$t, cwd:$c, tool_input:{file_path:$f}}')
    echo "$input" | "$HOOK" >/dev/null 2>&1
    rc=$?
    if [ "$expect" = "block" ]; then
        if [ "$rc" = "2" ]; then PASS=$((PASS + 1)); echo "PASS: $name"
        else FAIL=$((FAIL + 1)); echo "FAIL: $name (expected block/exit2, got $rc)"; fi
    else
        if [ "$rc" = "0" ]; then PASS=$((PASS + 1)); echo "PASS: $name"
        else FAIL=$((FAIL + 1)); echo "FAIL: $name (expected allow/exit0, got $rc)"; fi
    fi
}

# --- the bug: must block ---
run_case "Edit escapes to main checkout"      "Edit"  "$WT" "$REPO/packages/rrweb/src/record/foo.ts" block
run_case "Write escapes to main checkout"     "Write" "$WT" "$REPO/src/index.ts"                      block
run_case "MultiEdit escapes to main checkout" "MultiEdit" "$WT" "$REPO/README.md"                     block
run_case "escape from a worktree subdir"      "Edit"  "$WT/packages/a" "$REPO/packages/a/b.ts"        block
run_case "escape to repo root file"           "Write" "$WT" "$REPO/package.json"                      block

# --- legitimate edits inside the worktree: must allow ---
run_case "in-worktree absolute path"          "Edit"  "$WT" "$WT/packages/rrweb/src/record/foo.ts"    allow
run_case "in-worktree repo-root file"         "Write" "$WT" "$WT/package.json"                        allow
run_case "in-worktree from subdir"            "Edit"  "$WT/packages/a" "$WT/packages/a/b.ts"          allow
run_case "relative path (resolves in wt)"     "Edit"  "$WT" "packages/rrweb/src/record/foo.ts"        allow
run_case "relative dotslash path"             "Write" "$WT" "./src/index.ts"                          allow

# --- not a worktree session: hook inactive, must allow ---
run_case "normal repo, absolute under repo"   "Edit"  "$REPO" "$REPO/packages/a/b.ts"                 allow
run_case "normal repo, relative"              "Write" "$REPO" "src/index.ts"                          allow

# --- outside the repo entirely: not this guard's concern, allow ---
run_case "absolute path outside repo"         "Edit"  "$WT" "/etc/hosts"                              allow
run_case "absolute path other project"        "Write" "$WT" "/home/dev/other/file.ts"                allow

# --- wrong tool: allow ---
run_case "Bash tool ignored"                  "Bash"  "$WT" "$REPO/packages/a/b.ts"                   allow
run_case "Read tool ignored"                  "Read"  "$WT" "$REPO/packages/a/b.ts"                   allow

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
