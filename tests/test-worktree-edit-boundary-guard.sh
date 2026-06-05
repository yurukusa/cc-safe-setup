#!/bin/bash
# Tests for worktree-edit-boundary-guard.sh
# Run: bash tests/test-worktree-edit-boundary-guard.sh
set -u

PASS=0
FAIL=0
HOOK="$(cd "$(dirname "$0")/.." && pwd)/examples/worktree-edit-boundary-guard.sh"

# Build an isolated test scaffold:
#   $SCAFFOLD/main           (main checkout on 'master')
#   $SCAFFOLD/main/.git/worktrees/wt-a  (worktree metadata)
#   $SCAFFOLD/wt-a           (worktree working tree on branch 'wt')
SCAFFOLD=$(mktemp -d -t worktree-guard-test.XXXXXX)
trap 'rm -rf "$SCAFFOLD"' EXIT

(
    cd "$SCAFFOLD" || exit 1
    mkdir main && cd main
    git init -q
    git config user.email test@example.invalid
    git config user.name test
    git config commit.gpgsign false
    echo "main" > README.md
    git add README.md
    git commit -q -m "initial"
    git checkout -q -b wt 2>/dev/null
    git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null
    # Create a worktree on a separate branch
    git checkout -q -b feature 2>/dev/null
    git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null
    git worktree add -q ../wt-a feature 2>/dev/null
)

MAIN_TOP="$SCAFFOLD/main"
WT_TOP="$SCAFFOLD/wt-a"

if [ ! -d "$WT_TOP" ]; then
    echo "FATAL: scaffold setup failed — worktree not created"
    exit 1
fi

run_hook() {
    local cwd="$1" json="$2" expected_exit="$3" desc="$4" mode_env="${5:-}"
    local actual_exit=0
    local env_prefix=""
    [ -n "$mode_env" ] && env_prefix="$mode_env "
    actual_exit=0
    pushd "$cwd" >/dev/null
    if [ -n "$mode_env" ]; then
        echo "$json" | env $mode_env bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    else
        echo "$json" | bash "$HOOK" > /dev/null 2>/dev/null || actual_exit=$?
    fi
    popd >/dev/null
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    fi
}

echo "worktree-edit-boundary-guard.sh tests"
echo ""
echo "Scaffold: $SCAFFOLD"
echo "  Main:     $MAIN_TOP"
echo "  Worktree: $WT_TOP"
echo ""

# === Group A: not in a git repo or main checkout (pass-through) ===
echo "Group A: outside worktree (pass-through)"

run_hook "/tmp" \
    '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/anywhere.txt"}}' \
    0 "non-git dir: Edit passes through"

run_hook "$MAIN_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$MAIN_TOP"'/README.md"}}' \
    0 "main checkout (not worktree): Edit own file passes"

run_hook "$MAIN_TOP" \
    '{"tool_name":"Write","tool_input":{"file_path":"/etc/anywhere.txt"}}' \
    0 "main checkout (not worktree): Write to outside passes (different hook handles this)"

# === Group B: worktree, target inside worktree (pass-through) ===
echo ""
echo "Group B: in worktree, target inside (pass-through)"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$WT_TOP"'/README.md"}}' \
    0 "worktree: edit absolute path inside worktree passes"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"README.md"}}' \
    0 "worktree: edit relative path inside worktree passes"

run_hook "$WT_TOP" \
    '{"tool_name":"Write","tool_input":{"file_path":"new-file.txt"}}' \
    0 "worktree: Write to new file inside worktree passes"

run_hook "$WT_TOP" \
    '{"tool_name":"NotebookEdit","tool_input":{"file_path":"'"$WT_TOP"'/inside.ipynb"}}' \
    0 "worktree: NotebookEdit inside worktree passes"

# === Group C: worktree, target outside (warn default) ===
echo ""
echo "Group C: in worktree, target outside (warn default — exit 0)"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$MAIN_TOP"'/README.md"}}' \
    0 "worktree: edit absolute path into main checkout (warn default)"

run_hook "$WT_TOP" \
    '{"tool_name":"Write","tool_input":{"file_path":"'"$MAIN_TOP"'/new-file.txt"}}' \
    0 "worktree: Write to main checkout (warn default)"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"../main/README.md"}}' \
    0 "worktree: relative ../main/ escapes warn default"

run_hook "$WT_TOP" \
    '{"tool_name":"NotebookEdit","tool_input":{"file_path":"'"$MAIN_TOP"'/outside.ipynb"}}' \
    0 "worktree: NotebookEdit into main checkout (warn default)"

# === Group D: worktree, target outside, block mode ===
echo ""
echo "Group D: in worktree, target outside, MODE=block (exit 2)"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$MAIN_TOP"'/README.md"}}' \
    2 "block: edit into main checkout returns exit 2" \
    "CC_WORKTREE_BOUNDARY_MODE=block"

run_hook "$WT_TOP" \
    '{"tool_name":"Write","tool_input":{"file_path":"../main/file.txt"}}' \
    2 "block: relative escape returns exit 2" \
    "CC_WORKTREE_BOUNDARY_MODE=block"

# Inside worktree still passes in block mode
run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$WT_TOP"'/README.md"}}' \
    0 "block mode: inside worktree still passes" \
    "CC_WORKTREE_BOUNDARY_MODE=block"

# === Group E: tool filtering ===
echo ""
echo "Group E: non-edit tools (pass-through)"

run_hook "$WT_TOP" \
    '{"tool_name":"Read","tool_input":{"file_path":"'"$MAIN_TOP"'/README.md"}}' \
    0 "Read tool: pass-through even reading outside worktree"

run_hook "$WT_TOP" \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    0 "Bash tool: pass-through"

run_hook "$WT_TOP" \
    '{"tool_name":"Glob","tool_input":{"pattern":"*"}}' \
    0 "Glob tool: pass-through"

# === Group F: malformed/empty input ===
echo ""
echo "Group F: malformed/empty input (graceful)"

run_hook "$WT_TOP" \
    '{}' \
    0 "empty JSON: pass-through"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit"}' \
    0 "missing tool_input: pass-through"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{}}' \
    0 "missing file_path: pass-through"

run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":""}}' \
    0 "empty file_path: pass-through"

# === Group G: quiet mode (no stderr, but still appropriate exit) ===
echo ""
echo "Group G: quiet mode"

# Quiet + warn = exit 0, silent
run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$MAIN_TOP"'/README.md"}}' \
    0 "quiet+warn: exit 0 silent" \
    "CC_WORKTREE_BOUNDARY_QUIET=1"

# Quiet + block = exit 2, silent
run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$MAIN_TOP"'/README.md"}}' \
    2 "quiet+block: exit 2 silent" \
    "CC_WORKTREE_BOUNDARY_QUIET=1 CC_WORKTREE_BOUNDARY_MODE=block"

# === Group H: edge cases ===
echo ""
echo "Group H: edge cases"

# Sibling path with shared prefix (must not be matched as inside)
run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"${WT_TOP}-sibling"'/file.txt"}}' \
    0 "sibling path with shared prefix is outside (warn default)"

# Worktree's own subdirectory
run_hook "$WT_TOP" \
    '{"tool_name":"Edit","tool_input":{"file_path":"'"$WT_TOP"'/sub/dir/file.txt"}}' \
    0 "worktree subdirectory is inside"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL))"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    exit 1
fi
