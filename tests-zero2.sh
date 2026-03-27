#!/bin/bash
# Tests for 21 hooks with zero existing test_ex coverage
# Run via: source this file after test_ex function is defined, or append to test.sh

# --- package-script-guard.sh (PreToolUse, Edit) ---
echo "package-script-guard.sh:"
test_ex package-script-guard.sh '{"tool_input":{"file_path":"package.json","old_string":"\"scripts\"","new_string":"\"scripts\": {\"test\":\"jest\"}"}}' 0 "warns on scripts change but allows (exit 0)"
test_ex package-script-guard.sh '{"tool_input":{"file_path":"package.json","old_string":"\"dependencies\"","new_string":"\"dependencies\": {}"}}' 0 "warns on dependencies change but allows (exit 0)"
test_ex package-script-guard.sh '{"tool_input":{"file_path":"package.json","old_string":"\"name\"","new_string":"\"name\": \"foo\""}}' 0 "non-scripts edit passes silently"
test_ex package-script-guard.sh '{"tool_input":{"file_path":"src/index.js","old_string":"a","new_string":"b"}}' 0 "non-package.json file skipped"
echo ""

# --- permission-audit-log.sh (PostToolUse) ---
echo "permission-audit-log.sh:"
test_ex permission-audit-log.sh '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' 0 "logs Bash tool (allow)"
test_ex permission-audit-log.sh '{"tool_name":"Edit","tool_input":{"file_path":"src/main.ts"}}' 0 "logs Edit tool (allow)"
test_ex permission-audit-log.sh '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' 0 "logs Read tool (allow)"
test_ex permission-audit-log.sh '{}' 0 "empty input no tool_name (allow)"
echo ""

# --- pip-venv-guard.sh (PreToolUse, Bash) ---
echo "pip-venv-guard.sh:"
test_ex pip-venv-guard.sh '{"tool_input":{"command":"pip install requests"}}' 0 "pip install outside venv warns but allows"
test_ex pip-venv-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "non-pip command passes"
test_ex pip-venv-guard.sh '{"tool_input":{"command":"pip freeze"}}' 0 "pip freeze (not install) passes"
echo ""

# --- prompt-length-guard.sh (UserPromptSubmit) ---
echo "prompt-length-guard.sh:"
test_ex prompt-length-guard.sh '{"prompt":"short prompt"}' 0 "short prompt passes (allow)"
test_ex prompt-length-guard.sh '{"prompt":"'"$(python3 -c "print('x'*6000)")"'"}' 0 "long prompt warns but allows (exit 0)"
test_ex prompt-length-guard.sh '{}' 0 "empty prompt passes (allow)"
echo ""

# --- reinject-claudemd.sh (SessionStart) ---
echo "reinject-claudemd.sh:"
test_ex reinject-claudemd.sh '{}' 0 "session start outputs rules (allow)"
test_ex reinject-claudemd.sh '{"session_id":"abc123"}' 0 "with session_id (allow)"
test_ex reinject-claudemd.sh '' 0 "empty input (allow)"
echo ""

# --- relative-path-guard.sh (PreToolUse, Edit|Write) ---
echo "relative-path-guard.sh:"
test_ex relative-path-guard.sh '{"tool_input":{"file_path":"src/main.ts"}}' 0 "relative path warns but allows (exit 0)"
test_ex relative-path-guard.sh '{"tool_input":{"file_path":"/home/user/project/src/main.ts"}}' 0 "absolute path passes silently (allow)"
test_ex relative-path-guard.sh '{"tool_input":{"file_path":"./config.json"}}' 0 "dot-relative path warns but allows (exit 0)"
test_ex relative-path-guard.sh '{"tool_input":{}}' 0 "no file_path skipped (allow)"
echo ""

# --- revert-helper.sh (Stop) ---
echo "revert-helper.sh:"
test_ex revert-helper.sh '{"stop_reason":"user_request"}' 0 "stop event passes (allow)"
test_ex revert-helper.sh '{}' 0 "empty stop reason passes (allow)"
test_ex revert-helper.sh '{"stop_reason":"error"}' 0 "error stop passes (allow)"
echo ""

# --- sensitive-regex-guard.sh (PostToolUse, Edit|Write) ---
echo "sensitive-regex-guard.sh:"
test_ex sensitive-regex-guard.sh '{"tool_input":{"new_string":"const re = /(a+)+$/"}}' 0 "ReDoS pattern warns but allows (exit 0)"
test_ex sensitive-regex-guard.sh '{"tool_input":{"new_string":"const re = /^[a-z]+$/"}}' 0 "safe regex passes silently (allow)"
test_ex sensitive-regex-guard.sh '{"tool_input":{"new_string":"(.*)+test"}}' 0 "nested quantifier (.*)+ warns but allows"
test_ex sensitive-regex-guard.sh '{"tool_input":{"content":"no regex here"}}' 0 "no regex content passes (allow)"
echo ""

# --- session-checkpoint.sh (Stop) ---
echo "session-checkpoint.sh:"
test_ex session-checkpoint.sh '{"stop_reason":"user_request"}' 0 "saves checkpoint on stop (allow)"
test_ex session-checkpoint.sh '{}' 0 "empty stop reason saves checkpoint (allow)"
test_ex session-checkpoint.sh '{"stop_reason":"error"}' 0 "error stop saves checkpoint (allow)"
echo ""

# --- session-handoff.sh (Stop) ---
echo "session-handoff.sh:"
test_ex session-handoff.sh '{"stop_reason":"user_request"}' 0 "writes handoff on stop (allow)"
test_ex session-handoff.sh '{}' 0 "empty input writes handoff (allow)"
test_ex session-handoff.sh '{"stop_reason":"crash"}' 0 "crash stop writes handoff (allow)"
echo ""

# --- session-summary-stop.sh (Stop) ---
echo "session-summary-stop.sh:"
test_ex session-summary-stop.sh '{"stop_reason":"user_request"}' 0 "outputs summary on stop (allow)"
test_ex session-summary-stop.sh '{}' 0 "empty input outputs summary (allow)"
test_ex session-summary-stop.sh '{"stop_reason":"timeout"}' 0 "timeout stop outputs summary (allow)"
echo ""

# --- session-token-counter.sh (PostToolUse) ---
echo "session-token-counter.sh:"
test_ex session-token-counter.sh '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0 "increments counter for Bash (allow)"
test_ex session-token-counter.sh '{"tool_name":"Edit","tool_input":{"file_path":"foo.ts"}}' 0 "increments counter for Edit (allow)"
test_ex session-token-counter.sh '{}' 0 "empty tool_name skipped (allow)"
echo ""

# --- stale-env-guard.sh (PreToolUse, Bash) ---
echo "stale-env-guard.sh:"
test_ex stale-env-guard.sh '{"tool_input":{"command":"deploy production"}}' 0 "deploy command checks .env age (allow)"
test_ex stale-env-guard.sh '{"tool_input":{"command":"source .env"}}' 0 "source .env checks age (allow)"
test_ex stale-env-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "non-deploy command skipped (allow)"
test_ex stale-env-guard.sh '{"tool_input":{"command":"cat .env"}}' 0 "cat .env checks age (allow)"
echo ""

# --- test-coverage-guard.sh (PreToolUse, Bash) ---
echo "test-coverage-guard.sh:"
test_ex test-coverage-guard.sh '{"tool_input":{"command":"git commit -m \"feat: add login\""}}' 0 "git commit warns if no tests but allows (exit 0)"
test_ex test-coverage-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "non-commit command skipped (allow)"
test_ex test-coverage-guard.sh '{"tool_input":{"command":"git status"}}' 0 "git status skipped (allow)"
echo ""

# --- timeout-guard.sh (PreToolUse, Bash) ---
echo "timeout-guard.sh:"
test_ex timeout-guard.sh '{"tool_input":{"command":"npm start"}}' 0 "npm start warns but allows (exit 0)"
test_ex timeout-guard.sh '{"tool_input":{"command":"npm start","run_in_background":true}}' 0 "npm start with background no warn (allow)"
test_ex timeout-guard.sh '{"tool_input":{"command":"ls -la"}}' 0 "safe command passes (allow)"
test_ex timeout-guard.sh '{"tool_input":{"command":"tail -f /var/log/syslog"}}' 0 "tail -f warns but allows (exit 0)"
echo ""

# --- timezone-guard.sh (PreToolUse, Bash) ---
echo "timezone-guard.sh:"
test_ex timezone-guard.sh '{"tool_input":{"command":"TZ=America/New_York date"}}' 0 "non-UTC TZ warns but allows (exit 0)"
test_ex timezone-guard.sh '{"tool_input":{"command":"TZ=UTC date"}}' 0 "UTC TZ passes silently (allow)"
test_ex timezone-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "no timezone command passes (allow)"
echo ""

# --- todo-check.sh (PostToolUse, Bash) ---
echo "todo-check.sh:"
test_ex todo-check.sh '{"tool_input":{"command":"git commit -m \"fix: cleanup\""}}' 0 "git commit checks TODOs (allow)"
test_ex todo-check.sh '{"tool_input":{"command":"echo hello"}}' 0 "non-commit command skipped (allow)"
test_ex todo-check.sh '{"tool_input":{"command":"git status"}}' 0 "git status skipped (allow)"
echo ""

# --- typescript-strict-guard.sh (PostToolUse, Edit) ---
echo "typescript-strict-guard.sh:"
test_ex typescript-strict-guard.sh '{"tool_input":{"file_path":"tsconfig.json","new_string":"\"strict\": false"}}' 0 "strict false warns but allows (exit 0)"
test_ex typescript-strict-guard.sh '{"tool_input":{"file_path":"tsconfig.json","new_string":"\"strict\": true"}}' 0 "strict true passes silently (allow)"
test_ex typescript-strict-guard.sh '{"tool_input":{"file_path":"src/app.ts","new_string":"const x = 1"}}' 0 "non-tsconfig file skipped (allow)"
test_ex typescript-strict-guard.sh '{"tool_input":{"file_path":"tsconfig.json","new_string":"\"target\": \"es2020\""}}' 0 "non-strict edit passes (allow)"
echo ""

# --- typosquat-guard.sh (PreToolUse, Bash) ---
echo "typosquat-guard.sh:"
test_ex typosquat-guard.sh '{"tool_input":{"command":"npm install loadsh"}}' 0 "typosquat loadsh warns but allows (exit 0)"
test_ex typosquat-guard.sh '{"tool_input":{"command":"npm install lodash"}}' 0 "correct lodash passes (allow)"
test_ex typosquat-guard.sh '{"tool_input":{"command":"npm install expresss"}}' 0 "typosquat expresss warns but allows (exit 0)"
test_ex typosquat-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "non-install command skipped (allow)"
echo ""

# --- uncommitted-changes-stop.sh (Stop) ---
echo "uncommitted-changes-stop.sh:"
test_ex uncommitted-changes-stop.sh '{}' 0 "stop event checks uncommitted changes (allow)"
test_ex uncommitted-changes-stop.sh '{"stop_reason":"user_request"}' 0 "user stop checks changes (allow)"
test_ex uncommitted-changes-stop.sh '{"stop_reason":"error"}' 0 "error stop checks changes (allow)"
echo ""

# --- worktree-cleanup-guard.sh (PreToolUse, Bash) ---
echo "worktree-cleanup-guard.sh:"
test_ex worktree-cleanup-guard.sh '{"tool_input":{"command":"git worktree remove feature-branch"}}' 0 "worktree remove warns if unmerged but allows (exit 0)"
test_ex worktree-cleanup-guard.sh '{"tool_input":{"command":"git worktree prune"}}' 0 "worktree prune warns if unmerged but allows (exit 0)"
test_ex worktree-cleanup-guard.sh '{"tool_input":{"command":"git worktree add /tmp/wt feature"}}' 0 "worktree add not matched (allow)"
test_ex worktree-cleanup-guard.sh '{"tool_input":{"command":"git status"}}' 0 "non-worktree command skipped (allow)"
echo ""
