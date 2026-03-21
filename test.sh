#!/bin/bash
# cc-safe-setup hook tests
# Run: bash test.sh
# All hooks are tested by piping JSON input and checking exit codes

set -euo pipefail

PASS=0
FAIL=0
SCRIPTS_JSON="$(dirname "$0")/scripts.json"

# Extract hook scripts from scripts.json
extract_hook() {
    python3 -c "import json; print(json.load(open('$SCRIPTS_JSON'))['$1'])" > "/tmp/test-$1.sh"
    chmod +x "/tmp/test-$1.sh"
}

test_hook() {
    local name="$1" input="$2" expected_exit="$3" desc="$4"
    local actual_exit=0
    echo "$input" | bash "/tmp/test-$name.sh" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "cc-safe-setup hook tests"
echo "========================"
echo ""

# --- destructive-guard ---
echo "destructive-guard:"
extract_hook "destructive-guard"
test_hook "destructive-guard" '{"tool_input":{"command":"ls -la"}}' 0 "safe command passes"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf /"}}' 2 "rm -rf / blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf ~/"}}' 2 "rm -rf ~/ blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf ../"}}' 2 "rm -rf ../ blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf node_modules"}}' 0 "rm -rf node_modules allowed"
test_hook "destructive-guard" '{"tool_input":{"command":"git reset --hard"}}' 2 "git reset --hard blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"git reset --soft HEAD~1"}}' 0 "git reset --soft allowed"
test_hook "destructive-guard" '{"tool_input":{"command":"git clean -fd"}}' 2 "git clean -fd blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"chmod -R 777 /"}}' 2 "chmod 777 / blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"find / -delete"}}' 2 "find / -delete blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"echo git reset --hard"}}' 0 "git reset in echo not blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"sudo rm -rf /home"}}' 2 "sudo rm -rf blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"sudo apt install jq"}}' 0 "safe sudo command allowed"
echo ""

# --- branch-guard ---
echo "branch-guard:"
extract_hook "branch-guard"
test_hook "branch-guard" '{"tool_input":{"command":"git push origin feature-branch"}}' 0 "push to feature allowed"
test_hook "branch-guard" '{"tool_input":{"command":"git push -u origin my-branch"}}' 0 "push -u to branch allowed"
test_hook "branch-guard" '{"tool_input":{"command":"git push origin main"}}' 2 "push to main blocked"
test_hook "branch-guard" '{"tool_input":{"command":"git push origin master"}}' 2 "push to master blocked"
test_hook "branch-guard" '{"tool_input":{"command":"git push --force origin feature"}}' 2 "force push blocked"
test_hook "branch-guard" '{"tool_input":{"command":"git push -f origin feature"}}' 2 "force push -f blocked"
test_hook "branch-guard" '{"tool_input":{"command":"git push --force-with-lease origin feature"}}' 2 "force-with-lease blocked"
test_hook "branch-guard" '{"tool_input":{"command":"git status"}}' 0 "non-push git command passes"
test_hook "branch-guard" '{"tool_input":{"command":"npm install"}}' 0 "non-git command passes"
echo ""

# --- secret-guard ---
echo "secret-guard:"
extract_hook "secret-guard"
test_hook "secret-guard" '{"tool_input":{"command":"git add src/index.js"}}' 0 "git add normal file allowed"
test_hook "secret-guard" '{"tool_input":{"command":"git add .env"}}' 2 "git add .env blocked"
test_hook "secret-guard" '{"tool_input":{"command":"git add .env.local"}}' 2 "git add .env.local blocked"
test_hook "secret-guard" '{"tool_input":{"command":"git add credentials.json"}}' 2 "git add credentials.json blocked"
test_hook "secret-guard" '{"tool_input":{"command":"git add id_rsa"}}' 2 "git add id_rsa blocked"
test_hook "secret-guard" '{"tool_input":{"command":"git add server.key"}}' 2 "git add .key file blocked"
test_hook "secret-guard" '{"tool_input":{"command":"npm install"}}' 0 "non-git command passes"
test_hook "secret-guard" '{"tool_input":{"command":"git commit -m test"}}' 0 "git commit passes"
echo ""

# --- comment-strip ---
echo "comment-strip:"
extract_hook "comment-strip"
# comment-strip outputs JSON on stdout when it modifies, exit 0 always
local_exit=0
result=$(echo '{"tool_input":{"command":"# check status\ngit status"}}' | bash /tmp/test-comment-strip.sh 2>/dev/null) || local_exit=$?
if [ "$local_exit" -eq 0 ] && echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'git status' in d['hookSpecificOutput']['updatedInput']['command']" 2>/dev/null; then
    echo "  PASS: strips comment, returns clean command"
    PASS=$((PASS + 1))
else
    echo "  FAIL: comment stripping"
    FAIL=$((FAIL + 1))
fi
result2=$(echo '{"tool_input":{"command":"git status"}}' | bash /tmp/test-comment-strip.sh 2>/dev/null) || true
if [ -z "$result2" ]; then
    echo "  PASS: no-comment command passes through unchanged"
    PASS=$((PASS + 1))
else
    echo "  FAIL: should pass through without modification"
    FAIL=$((FAIL + 1))
fi
echo ""

# --- cd-git-allow ---
echo "cd-git-allow:"
extract_hook "cd-git-allow"
local_exit=0
result=$(echo '{"tool_input":{"command":"cd /tmp && git log"}}' | bash /tmp/test-cd-git-allow.sh 2>/dev/null) || local_exit=$?
if [ "$local_exit" -eq 0 ] && echo "$result" | grep -q "permissionDecision"; then
    echo "  PASS: cd+git log auto-approved"
    PASS=$((PASS + 1))
else
    echo "  FAIL: cd+git log should be auto-approved"
    FAIL=$((FAIL + 1))
fi
result2=$(echo '{"tool_input":{"command":"cd /tmp && git push origin main"}}' | bash /tmp/test-cd-git-allow.sh 2>/dev/null) || true
if ! echo "$result2" | grep -q "permissionDecision" 2>/dev/null; then
    echo "  PASS: cd+git push NOT auto-approved"
    PASS=$((PASS + 1))
else
    echo "  FAIL: cd+git push should not be auto-approved"
    FAIL=$((FAIL + 1))
fi
test_hook "cd-git-allow" '{"tool_input":{"command":"npm install"}}' 0 "non-cd command passes"
echo ""

# --- context-monitor ---
echo "context-monitor:"
extract_hook "context-monitor"
# context-monitor always exits 0 (never blocks)
test_hook "context-monitor" '{"tool_input":{"command":"ls"}}' 0 "always exits 0 (non-blocking)"
echo ""

# --- syntax-check ---
echo "syntax-check:"
extract_hook "syntax-check"
# Create a valid and invalid Python file for testing
echo "x = 1" > /tmp/test-valid.py
echo "x = (" > /tmp/test-invalid.py
# syntax-check always exits 0 (reports errors but doesn't block)
test_hook "syntax-check" '{"tool_input":{"file_path":"/tmp/test-valid.py"}}' 0 "valid Python passes silently"
test_hook "syntax-check" '{"tool_input":{"file_path":"/tmp/test-invalid.py"}}' 0 "invalid Python reports but exits 0"
test_hook "syntax-check" '{"tool_input":{"file_path":"/nonexistent/file.py"}}' 0 "nonexistent file exits 0"
rm -f /tmp/test-valid.py /tmp/test-invalid.py
echo ""

# --- destructive-guard edge cases ---
echo "destructive-guard-edge-cases:"
extract_hook "destructive-guard"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf /tmp/build"}}' 0 "rm -rf /tmp subdir allowed"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf dist"}}' 0 "rm -rf dist (safe dir) allowed"
test_hook "destructive-guard" '{"tool_input":{"command":"cat file | xargs rm"}}' 0 "pipe to rm (no -rf) passes"
test_hook "destructive-guard" '{"tool_input":{"command":"find . -name \"*.pyc\" -delete"}}' 0 "find . -delete (not /) allowed"
test_hook "destructive-guard" '{"tool_input":{"command":"  rm  -rf  /"}}' 2 "extra spaces still blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"rm -rf /var"}}' 2 "rm -rf /var blocked"
# git push --force is branch-guard's responsibility, not destructive-guard
test_hook "destructive-guard" '{"tool_input":{"command":"git push origin feature"}}' 0 "git push (non-destructive) passes"
echo ""

# --- secret-guard edge cases ---
echo "secret-guard-edge-cases:"
extract_hook "secret-guard"
test_hook "secret-guard" '{"tool_input":{"command":"git add .env.production"}}' 2 "git add .env.production blocked"
test_hook "secret-guard" '{"tool_input":{"command":"git add server.pem"}}' 2 "git add .pem file blocked"
# git add . / -A only blocked when .env exists in cwd
touch /tmp/.env-test-sentinel
(cd /tmp && ln -sf .env-test-sentinel .env && echo '{"tool_input":{"command":"git add ."}}' | bash /tmp/test-secret-guard.sh > /dev/null 2>/dev/null; exit_code=$?; rm -f .env; [ "$exit_code" -eq 2 ] && echo "  PASS: git add . blocked when .env exists" && exit 0 || echo "  FAIL: git add . should block when .env exists" && exit 1) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
(cd /tmp && ln -sf .env-test-sentinel .env && echo '{"tool_input":{"command":"git add -A"}}' | bash /tmp/test-secret-guard.sh > /dev/null 2>/dev/null; exit_code=$?; rm -f .env; [ "$exit_code" -eq 2 ] && echo "  PASS: git add -A blocked when .env exists" && exit 0 || echo "  FAIL: git add -A should block when .env exists" && exit 1) && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))
rm -f /tmp/.env-test-sentinel
test_hook "secret-guard" '{"tool_input":{"command":"git add src/ tests/"}}' 0 "git add specific dirs allowed"
echo ""

# --- destructive-guard: git checkout/switch force ---
echo "destructive-guard-force:"
extract_hook "destructive-guard"
test_hook "destructive-guard" '{"tool_input":{"command":"git checkout --force main"}}' 2 "git checkout --force blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"git switch --force feature"}}' 2 "git switch --force blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"git switch --discard-changes main"}}' 2 "git switch --discard-changes blocked"
test_hook "destructive-guard" '{"tool_input":{"command":"git checkout main"}}' 0 "git checkout (no force) allowed"
test_hook "destructive-guard" '{"tool_input":{"command":"git switch feature"}}' 0 "git switch (no force) allowed"
echo ""

# --- Edge case: malformed input ---
echo "edge-cases:"
extract_hook "destructive-guard"
# Empty input should not crash
echo '' | bash /tmp/test-destructive-guard.sh 2>/dev/null; [ $? -eq 0 ] && echo "  PASS: empty input handled" && PASS=$((PASS + 1)) || { echo "  FAIL: empty input"; FAIL=$((FAIL + 1)); }
# Malformed JSON should not produce stderr
STDERR=$(echo 'not json' | bash /tmp/test-destructive-guard.sh 2>&1 >/dev/null)
if [ -z "$STDERR" ]; then
    echo "  PASS: malformed JSON silent (no stderr)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: malformed JSON produced stderr: $STDERR"
    FAIL=$((FAIL + 1))
fi
echo ""

# --- CLI smoke tests ---
echo "CLI:"
node "$(dirname "$0")/index.mjs" --help > /dev/null 2>&1 && echo "  PASS: --help exits 0" && PASS=$((PASS + 1)) || { echo "  FAIL: --help"; FAIL=$((FAIL + 1)); }
node "$(dirname "$0")/index.mjs" --dry-run > /dev/null 2>&1 && echo "  PASS: --dry-run exits 0" && PASS=$((PASS + 1)) || { echo "  FAIL: --dry-run"; FAIL=$((FAIL + 1)); }
# --status exits 0 when hooks installed, 1 when not (CI-friendly)
STATUS_EXIT=0
node "$(dirname "$0")/index.mjs" --status > /dev/null 2>&1 || STATUS_EXIT=$?
if [ "$STATUS_EXIT" -eq 0 ] || [ "$STATUS_EXIT" -eq 1 ]; then
    echo "  PASS: --status exits $STATUS_EXIT (0=installed, 1=missing)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: --status (unexpected exit $STATUS_EXIT)"
    FAIL=$((FAIL + 1))
fi
echo ""

# --- Summary ---
echo "========================"
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    echo "FAILURES: $FAIL"
    exit 1
else
    echo "All tests passed!"
fi
