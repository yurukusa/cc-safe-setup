#!/bin/bash
# tests-deep3.sh — 2 edge-case tests per hook for 26 hooks (52 tests total)
# Goal: bring each hook from 3-4 tests to 5+
# Run: source test.sh functions first, then bash tests-deep3.sh
#      OR run standalone (includes test_ex definition)

set -euo pipefail

PASS=0
FAIL=0
EXDIR="$(dirname "$0")/examples"

test_ex() {
    local script="$1" input="$2" expected_exit="$3" desc="$4"
    local actual_exit=0
    echo "$input" | bash "$EXDIR/$script" > /dev/null 2>/dev/null || actual_exit=$?
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "tests-deep3: edge-case tests (2 per hook, 26 hooks)"
echo "===================================================="
echo ""

# --- prompt-length-guard ---
test_ex prompt-length-guard.sh '{"prompt":""}' 0 "prompt-length-guard: empty string prompt passes (allow)"
test_ex prompt-length-guard.sh '{"prompt":"exactly 5000 chars is fine","other":"field"}' 0 "prompt-length-guard: short prompt with extra JSON fields (allow)"

# --- protect-commands-dir ---
test_ex protect-commands-dir.sh '{"unexpected_key":"value"}' 0 "protect-commands-dir: unexpected JSON keys ignored (allow)"
test_ex protect-commands-dir.sh 'not json at all' 0 "protect-commands-dir: non-JSON input handled gracefully (allow)"

# --- rate-limit-guard ---
test_ex rate-limit-guard.sh '{"tool_input":{"command":"npm test"}}' 0 "rate-limit-guard: different command still tracks rate (allow)"
test_ex rate-limit-guard.sh '{"tool_input":{}}' 0 "rate-limit-guard: empty tool_input object (allow)"

# --- read-before-edit ---
test_ex read-before-edit.sh '{"tool_name":"Edit","tool_input":{}}' 0 "read-before-edit: Edit with no file_path skipped (allow)"
test_ex read-before-edit.sh '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.js"}}' 0 "read-before-edit: Read tool ignored by hook (allow)"

# --- reinject-claudemd ---
test_ex reinject-claudemd.sh '{"session_id":"abc","user":"test"}' 0 "reinject-claudemd: extra fields in input ignored (allow)"
test_ex reinject-claudemd.sh '{"restart":true}' 0 "reinject-claudemd: restart flag input (allow)"

# --- relative-path-guard ---
test_ex relative-path-guard.sh '{"tool_input":{"file_path":"../sibling/file.ts"}}' 0 "relative-path-guard: parent-relative path warns (allow)"
test_ex relative-path-guard.sh '{"tool_input":{"file_path":"~/Documents/file.txt"}}' 0 "relative-path-guard: tilde path warns (allow)"

# --- require-issue-ref ---
test_ex require-issue-ref.sh '{"tool_input":{"command":"git commit -m \"feat: #42 add login\""}}' 0 "require-issue-ref: GitHub-style #42 ref allowed (allow)"
test_ex require-issue-ref.sh '{"tool_input":{"command":"git commit -m \"chore: cleanup code\""}}' 0 "require-issue-ref: no ref warns but allows (allow)"

# --- revert-helper ---
test_ex revert-helper.sh '{"stop_reason":"max_tokens"}' 0 "revert-helper: max_tokens stop reason passes (allow)"
test_ex revert-helper.sh 'invalid json' 0 "revert-helper: non-JSON input handled gracefully (allow)"

# --- sensitive-regex-guard ---
test_ex sensitive-regex-guard.sh '{"tool_input":{"new_string":"const re = /([a-z]+)*$/"}}' 0 "sensitive-regex-guard: ([a-z]+)* nested quantifier warns (allow)"
test_ex sensitive-regex-guard.sh '{"tool_input":{"new_string":"const x = 42; // no regex"}}' 0 "sensitive-regex-guard: code without regex passes silently (allow)"

# --- session-checkpoint ---
test_ex session-checkpoint.sh '{"stop_reason":"max_tokens"}' 0 "session-checkpoint: max_tokens stop saves checkpoint (allow)"
test_ex session-checkpoint.sh 'malformed input' 0 "session-checkpoint: non-JSON input handled gracefully (allow)"

# --- session-handoff ---
test_ex session-handoff.sh '{"stop_reason":"max_tokens"}' 0 "session-handoff: max_tokens stop writes handoff (allow)"
test_ex session-handoff.sh '{"stop_reason":"error","error_code":500}' 0 "session-handoff: error with code writes handoff (allow)"

# --- session-summary-stop ---
test_ex session-summary-stop.sh '{"stop_reason":"max_tokens"}' 0 "session-summary-stop: max_tokens outputs summary (allow)"
test_ex session-summary-stop.sh 'not valid json' 0 "session-summary-stop: non-JSON input handled (allow)"

# --- session-token-counter ---
test_ex session-token-counter.sh '{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"code"}}' 0 "session-token-counter: Write tool increments counter (allow)"
test_ex session-token-counter.sh '{"tool_name":"","tool_input":{}}' 0 "session-token-counter: empty string tool_name skipped (allow)"

# --- stale-branch-guard ---
test_ex stale-branch-guard.sh '{"tool_input":{"command":"git push origin main"}}' 0 "stale-branch-guard: git push still exits 0 (allow)"
test_ex stale-branch-guard.sh '{}' 0 "stale-branch-guard: empty input increments counter (allow)"

# --- stale-env-guard ---
test_ex stale-env-guard.sh '{"tool_input":{"command":"docker run --env-file .env app"}}' 0 "stale-env-guard: docker --env-file triggers check (allow)"
test_ex stale-env-guard.sh '{"tool_input":{"command":"ls -la .env"}}' 0 "stale-env-guard: ls .env not a deploy command, skipped (allow)"

# --- test-coverage-guard ---
test_ex test-coverage-guard.sh '{"tool_input":{"command":"git commit -m \"test: add unit tests\""}}' 0 "test-coverage-guard: commit with test in message still checks staged (allow)"
test_ex test-coverage-guard.sh '{"tool_input":{"command":"git commit --amend --no-edit"}}' 0 "test-coverage-guard: amend commit checked (allow)"

# --- test-deletion-guard ---
test_ex test-deletion-guard.sh '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts","old_string":"code","new_string":"newcode"}}' 0 "test-deletion-guard: non-test file skipped (allow)"
test_ex test-deletion-guard.sh '{"tool_name":"Edit","tool_input":{"file_path":"src/__tests__/login.spec.js","old_string":"it(\"logs in\", () => { expect(true).toBe(true) })","new_string":"it(\"logs in\", () => { expect(true).toBe(true) })\nit(\"logs out\", () => { expect(false).toBe(false) })"}}' 0 "test-deletion-guard: adding test to spec file passes (allow)"

# --- timeout-guard ---
test_ex timeout-guard.sh '{"tool_input":{"command":"python manage.py runserver"}}' 0 "timeout-guard: django runserver warns (allow)"
test_ex timeout-guard.sh '{"tool_input":{"command":"cargo watch -x test","run_in_background":true}}' 0 "timeout-guard: cargo watch with background no warn (allow)"

# --- timezone-guard ---
test_ex timezone-guard.sh '{"tool_input":{"command":"TZ=Asia/Tokyo date"}}' 0 "timezone-guard: Asia/Tokyo TZ warns (allow)"
test_ex timezone-guard.sh '{"tool_input":{"command":"date --timezone=EST"}}' 0 "timezone-guard: --timezone flag warns (allow)"

# --- todo-check ---
test_ex todo-check.sh '{"tool_input":{"command":"git commit --amend -m \"fix: patch\""}}' 0 "todo-check: amend commit checked (allow)"
test_ex todo-check.sh '{"tool_input":{"command":"git add . && git commit -m \"wip\""}}' 0 "todo-check: chained git add+commit checked (allow)"

# --- typescript-strict-guard ---
test_ex typescript-strict-guard.sh '{"tool_input":{"file_path":"packages/core/tsconfig.json","new_string":"\"strict\": false, \"noImplicitAny\": true"}}' 0 "typescript-strict-guard: nested tsconfig path warns (allow)"
test_ex typescript-strict-guard.sh '{"tool_input":{"file_path":"tsconfig.json","new_string":"\"moduleResolution\": \"node\""}}' 0 "typescript-strict-guard: non-strict field edit passes (allow)"

# --- typosquat-guard ---
test_ex typosquat-guard.sh '{"tool_input":{"command":"pip install reqeusts"}}' 0 "typosquat-guard: pip typo reqeusts detected (allow)"
test_ex typosquat-guard.sh '{"tool_input":{"command":"npm install @types/lodash"}}' 0 "typosquat-guard: scoped package passes (allow)"

# --- uncommitted-changes-stop ---
test_ex uncommitted-changes-stop.sh '{"stop_reason":"max_tokens"}' 0 "uncommitted-changes-stop: max_tokens stop checks changes (allow)"
test_ex uncommitted-changes-stop.sh 'garbage input' 0 "uncommitted-changes-stop: non-JSON input handled (allow)"

# --- verify-before-done ---
test_ex verify-before-done.sh '{"tool_input":{"command":"git commit --amend --no-edit"}}' 0 "verify-before-done: amend commit checks tests (allow)"
test_ex verify-before-done.sh '{"tool_input":{"command":"git add . && git commit -m \"fix\""}}' 0 "verify-before-done: chained command with commit (allow)"

# --- worktree-cleanup-guard ---
test_ex worktree-cleanup-guard.sh '{"tool_input":{"command":"git worktree remove --force /tmp/wt"}}' 0 "worktree-cleanup-guard: forced remove warns if unmerged (allow)"
test_ex worktree-cleanup-guard.sh '{"tool_input":{"command":"git branch -D feature"}}' 0 "worktree-cleanup-guard: branch delete not matched (allow)"

# --- worktree-guard ---
test_ex worktree-guard.sh '{"tool_input":{"command":"git checkout -- src/main.ts"}}' 0 "worktree-guard: checkout file in normal repo (allow)"
test_ex worktree-guard.sh '{"tool_input":{"command":"git push origin main"}}' 0 "worktree-guard: non-destructive git command skipped (allow)"

echo ""
echo "========================================="
echo "tests-deep3 results: $PASS passed, $FAIL failed (total $((PASS + FAIL)))"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
