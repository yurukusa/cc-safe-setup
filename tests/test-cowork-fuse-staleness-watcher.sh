#!/bin/bash
# Tests for cowork-fuse-staleness-watcher.sh
set -euo pipefail

HOOK="$(dirname "$0")/../examples/cowork-fuse-staleness-watcher.sh"
PASS=0
FAIL=0

run_hook() {
    local cmd="$1"
    local cwd="${2:-/home/user/project}"
    local payload
    payload=$(jq -nc --arg cmd "$cmd" --arg cwd "$cwd" \
        '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}')
    echo "$payload" | bash "$HOOK" 2>&1 || true
}

# --- Test 1: Warns for git status in Cowork FUSE mount ---
output=$(run_hook "git status" "/sessions/abc123/mnt/havasu-chat")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns for git status in FUSE mount"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for git status in FUSE mount"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: Warns for git add in Cowork FUSE mount ---
output=$(run_hook "git add ." "/sessions/xyz789/mnt/myrepo")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns for git add in FUSE mount"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for git add in FUSE mount"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: Warns for git commit in Cowork FUSE mount ---
output=$(run_hook "git commit -m test" "/sessions/v43/mnt/havasu-chat")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns for git commit in FUSE mount"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for git commit in FUSE mount"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Silent for git rev-parse (ref-only, safe under wedge) ---
output=$(run_hook "git rev-parse HEAD" "/sessions/abc/mnt/repo")
if [ -z "$output" ]; then
    echo "  PASS: silent for git rev-parse (ref-only ops are safe)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should not warn for git rev-parse: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: Silent for git log (ref-only) ---
output=$(run_hook "git log --oneline -5" "/sessions/abc/mnt/repo")
if [ -z "$output" ]; then
    echo "  PASS: silent for git log (ref-only)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should not warn for git log: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: Silent for non-git commands in FUSE mount ---
output=$(run_hook "ls -la" "/sessions/abc/mnt/repo")
if [ -z "$output" ]; then
    echo "  PASS: silent for non-git command in FUSE mount"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should not warn for non-git command"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: Silent for git status OUTSIDE FUSE mount ---
output=$(run_hook "git status" "/home/user/normal-project")
if [ -z "$output" ]; then
    echo "  PASS: silent for git status outside FUSE mount"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should not warn outside FUSE mount: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: Warns when FUSE path appears in command (not cwd) ---
output=$(run_hook "git -C /sessions/abc/mnt/repo status" "/home/user")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns when FUSE path is in command argument"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn when FUSE path in command"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: References issue #62932 ---
output=$(run_hook "git status" "/sessions/abc/mnt/repo")
if echo "$output" | grep -q "#62932"; then
    echo "  PASS: references #62932"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should reference #62932"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: Mentions ref-walking as safe alternative ---
output=$(run_hook "git status" "/sessions/abc/mnt/repo")
if echo "$output" | grep -q "ref-walking"; then
    echo "  PASS: mentions ref-walking as safe alternative"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should mention ref-walking"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: Mentions Read/Edit/Write tools as authoritative ---
output=$(run_hook "git status" "/sessions/abc/mnt/repo")
if echo "$output" | grep -qE "Read.*Edit.*Write|first-class file tools"; then
    echo "  PASS: mentions Read/Edit/Write tools"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should mention first-class file tools"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: CC_COWORK_FUSE_QUIET suppresses recommendation block ---
payload=$(jq -nc --arg cmd "git status" --arg cwd "/sessions/abc/mnt/repo" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}')
output=$(echo "$payload" | CC_COWORK_FUSE_QUIET=1 bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "Recommended:"; then
    echo "  FAIL: CC_COWORK_FUSE_QUIET=1 should suppress recommendation"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: CC_COWORK_FUSE_QUIET=1 suppresses recommendation"
    PASS=$((PASS + 1))
fi

# --- Test 13: Recommendation shows by default ---
output=$(run_hook "git status" "/sessions/abc/mnt/repo")
if echo "$output" | grep -q "Recommended:"; then
    echo "  PASS: recommendation shown by default"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should show recommendation by default"
    FAIL=$((FAIL + 1))
fi

# --- Test 14: Custom CC_COWORK_FUSE_PATTERN override ---
payload=$(jq -nc --arg cmd "git status" --arg cwd "/custom/mount/repo" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}')
output=$(echo "$payload" | CC_COWORK_FUSE_PATTERN="/custom/mount/" bash "$HOOK" 2>&1 || true)
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: custom CC_COWORK_FUSE_PATTERN works"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should respect custom pattern"
    FAIL=$((FAIL + 1))
fi

# --- Test 15: Always exits 0 (advisory only) ---
echo "$payload" | bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 when fires (advisory only)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0 when fires, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 16: Exits 0 when silent ---
payload2=$(jq -nc --arg cmd "ls" --arg cwd "/home/user" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}')
echo "$payload2" | bash "$HOOK" >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then
    echo "  PASS: exits 0 when silent"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should exit 0 when silent, got $status"
    FAIL=$((FAIL + 1))
fi

# --- Test 17: Warns for git stash ---
output=$(run_hook "git stash" "/sessions/abc/mnt/repo")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns for git stash"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for git stash"
    FAIL=$((FAIL + 1))
fi

# --- Test 18: Warns for git restore ---
output=$(run_hook "git restore ." "/sessions/v37/mnt/havasu")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns for git restore"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for git restore"
    FAIL=$((FAIL + 1))
fi

# --- Test 19: Warns for git checkout -- (path discard) ---
output=$(run_hook "git checkout -- file.txt" "/sessions/abc/mnt/repo")
if echo "$output" | grep -q "Cowork FUSE mount detected"; then
    echo "  PASS: warns for git checkout -- (path discard)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should warn for git checkout --"
    FAIL=$((FAIL + 1))
fi

# --- Test 20: Silent for git checkout <branch> (branch switch, not worktree discard) ---
output=$(run_hook "git checkout main" "/sessions/abc/mnt/repo")
# Note: pure branch switch with no '-- ' or '.' is NOT in our matcher list.
# We deliberately don't warn for this to avoid noise on a routine op.
if [ -z "$output" ]; then
    echo "  PASS: silent for git checkout <branch>"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should not warn for branch switch: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 21: Mentions .git/config rewrite recovery ---
output=$(run_hook "git status" "/sessions/abc/mnt/repo")
if echo "$output" | grep -q ".git/config"; then
    echo "  PASS: mentions .git/config rewrite recovery"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should mention .git/config recovery"
    FAIL=$((FAIL + 1))
fi

# --- Test 22: Log file is written when CC_COWORK_FUSE_LOG set ---
LOG_FILE=$(mktemp /tmp/test-cowork-fuse-log.XXXXXX)
rm -f "$LOG_FILE"
payload=$(jq -nc --arg cmd "git status" --arg cwd "/sessions/abc/mnt/repo" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}')
echo "$payload" | CC_COWORK_FUSE_LOG="$LOG_FILE" bash "$HOOK" >/dev/null 2>&1
if [ -f "$LOG_FILE" ] && grep -q "git status" "$LOG_FILE"; then
    echo "  PASS: writes log entry when CC_COWORK_FUSE_LOG set"
    PASS=$((PASS + 1))
else
    echo "  FAIL: log file should contain entry"
    FAIL=$((FAIL + 1))
fi
rm -f "$LOG_FILE"

# --- Test 23: Handles missing tool_input gracefully ---
output=$(echo '{"tool_name":"Bash"}' | bash "$HOOK" 2>&1 || true)
if [ -z "$output" ]; then
    echo "  PASS: silent for missing tool_input"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should be silent for missing tool_input: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 24: Documents PreToolUse + Bash matcher ---
if grep -q "PreToolUse" "$HOOK" && grep -q "Bash" "$HOOK"; then
    echo "  PASS: documents PreToolUse + Bash matcher"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should document PreToolUse + Bash"
    FAIL=$((FAIL + 1))
fi

# --- Test 25: Header documents the SELECTIVE wedge nature ---
if grep -qi "selective" "$HOOK"; then
    echo "  PASS: hook header documents selective wedge"
    PASS=$((PASS + 1))
else
    echo "  FAIL: header should describe selective wedge"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "Tests: $((PASS + FAIL)) total, $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
