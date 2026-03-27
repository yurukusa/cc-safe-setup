# auto-approve-compound-git.sh (PermissionRequest — exit 0, outputs allow JSON for safe compound git)
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"cd src && git log --oneline"}}' 0 "allows compound cd + git log"
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"git add file.txt && git commit -m fix"}}' 0 "allows git add + git commit"
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"cd src && rm -rf dist"}}' 0 "passes through unsafe compound (no block, exit 0 no allow JSON)"
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"git status"}}' 0 "allows simple git status"

# auto-approve-readonly-tools.sh (PermissionRequest — exit 0, outputs allow for Read/Glob/Grep)
test_ex auto-approve-readonly-tools.sh '{"tool_name":"Read","tool_input":{"file_path":"foo.txt"}}' 0 "auto-approves Read tool"
test_ex auto-approve-readonly-tools.sh '{"tool_name":"Glob","tool_input":{"pattern":"*.ts"}}' 0 "auto-approves Glob tool"
test_ex auto-approve-readonly-tools.sh '{"tool_name":"Grep","tool_input":{"pattern":"foo"}}' 0 "auto-approves Grep tool"
test_ex auto-approve-readonly-tools.sh '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' 0 "ignores non-readonly tool (no allow JSON)"

# auto-mode-safe-commands.sh (PreToolUse — exit 0, outputs allow for safe commands)
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"cat README.md"}}' 0 "approves read-only cat"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"grep -r TODO src/"}}' 0 "approves text search grep"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"git status"}}' 0 "approves git read-only status"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"jq .name package.json"}}' 0 "approves jq processing"

# auto-stash-before-pull.sh (PreToolUse — exit 0 always, warns on stderr)
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"git pull origin main"}}' 0 "warns on git pull (exit 0)"
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"git merge feature"}}' 0 "warns on git merge (exit 0)"
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"git status"}}' 0 "ignores non-pull commands"
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-git commands"

# branch-name-check.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex branch-name-check.sh '{"tool_input":{"command":"git checkout -b feature/add-login"}}' 0 "conventional branch name OK"
test_ex branch-name-check.sh '{"tool_input":{"command":"git checkout -b my-random-branch"}}' 0 "warns non-conventional prefix (exit 0)"
test_ex branch-name-check.sh '{"tool_input":{"command":"git checkout -b feat/special@chars"}}' 0 "warns special chars (exit 0)"
test_ex branch-name-check.sh '{"tool_input":{"command":"git status"}}' 0 "ignores non-branch commands"

# branch-naming-convention.sh (PreToolUse — exit 0 always, warns on stderr)
test_ex branch-naming-convention.sh '{"tool_input":{"command":"git checkout -b feat/new-feature"}}' 0 "conventional feat/ OK"
test_ex branch-naming-convention.sh '{"tool_input":{"command":"git checkout -b fix/bug-123"}}' 0 "conventional fix/ OK"
test_ex branch-naming-convention.sh '{"tool_input":{"command":"git checkout -b random-branch"}}' 0 "warns non-conventional (exit 0)"
test_ex branch-naming-convention.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-git commands"

# classifier-fallback-allow.sh (PermissionRequest — exit 0, outputs allow for read-only)
test_ex classifier-fallback-allow.sh '{"tool_input":{"command":"cat README.md"}}' 0 "allows cat (read-only)"
test_ex classifier-fallback-allow.sh '{"tool_input":{"command":"git log --oneline"}}' 0 "allows git log (read-only)"
test_ex classifier-fallback-allow.sh '{"tool_input":{"command":"echo hello"}}' 0 "allows echo (shell builtin)"
test_ex classifier-fallback-allow.sh '{"tool_input":{"command":"rm -rf /"}}' 0 "no opinion on destructive (exit 0, no allow JSON)"
test_ex classifier-fallback-allow.sh '{"tool_input":{"command":"find /tmp -delete"}}' 0 "does not approve find with -delete"

# commit-message-check.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex commit-message-check.sh '{"tool_input":{"command":"git commit -m \"feat: add login\""}}' 0 "conventional commit OK (exit 0)"
test_ex commit-message-check.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-commit commands"
test_ex commit-message-check.sh '{"tool_input":{"command":"git status"}}' 0 "ignores git non-commit"

# compound-command-allow.sh (PreToolUse — exit 0, outputs allow for all-safe compounds)
test_ex compound-command-allow.sh '{"tool_input":{"command":"cd src && git log"}}' 0 "allows cd + git log"
test_ex compound-command-allow.sh '{"tool_input":{"command":"cat file.txt | grep TODO"}}' 0 "allows cat piped to grep"
test_ex compound-command-allow.sh '{"tool_input":{"command":"cd src && rm -rf dist"}}' 0 "no opinion on unsafe compound (exit 0, no allow JSON)"
test_ex compound-command-allow.sh '{"tool_input":{"command":"echo hello"}}' 0 "passes through simple command"

# compound-command-approver.sh (PreToolUse — exit 0, only handles compound commands)
test_ex compound-command-approver.sh '{"tool_input":{"command":"cd /app && git status"}}' 0 "approves cd + git status"
test_ex compound-command-approver.sh '{"tool_input":{"command":"npm test && npm run build"}}' 0 "approves npm test + npm run"
test_ex compound-command-approver.sh '{"tool_input":{"command":"cd /app && sudo rm -rf /"}}' 0 "no opinion on unsafe compound (exit 0)"
test_ex compound-command-approver.sh '{"tool_input":{"command":"git status"}}' 0 "ignores simple (non-compound) commands"

# debug-leftover-guard.sh (PreToolUse — exit 0 always, warns on stderr)
test_ex debug-leftover-guard.sh '{"tool_input":{"command":"git commit -m \"fix\""}}' 0 "checks staged changes on commit (exit 0)"
test_ex debug-leftover-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-commit commands"
test_ex debug-leftover-guard.sh '{"tool_input":{"command":"git status"}}' 0 "ignores git non-commit"

# dependency-version-pin.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"package.json","new_string":"\"lodash\": \"^4.17.21\""}}' 0 "warns on ^ range (exit 0)"
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"package.json","new_string":"\"lodash\": \"4.17.21\""}}' 0 "exact version OK (exit 0)"
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"src/main.ts","new_string":"console.log(1)"}}' 0 "ignores non-package.json"

# docker-prune-guard.sh (PreToolUse — exit 0 always, warns on stderr)
test_ex docker-prune-guard.sh '{"tool_input":{"command":"docker system prune"}}' 0 "warns on docker system prune (exit 0)"
test_ex docker-prune-guard.sh '{"tool_input":{"command":"docker system prune -af"}}' 0 "warns on docker system prune -af (exit 0)"
test_ex docker-prune-guard.sh '{"tool_input":{"command":"docker ps"}}' 0 "ignores docker ps"
test_ex docker-prune-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-docker commands"

# enforce-tests.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex enforce-tests.sh '{"tool_input":{"file_path":"/tmp/test_foo.py"}}' 0 "ignores test files"
test_ex enforce-tests.sh '{"tool_input":{"file_path":"/tmp/nonexistent.py"}}' 0 "ignores nonexistent files"
test_ex enforce-tests.sh '{"tool_input":{"file_path":"README.md"}}' 0 "ignores non-source files"

# env-drift-guard.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex env-drift-guard.sh '{"tool_input":{"file_path":"src/main.ts"}}' 0 "ignores non-env files"
test_ex env-drift-guard.sh '{"tool_input":{"file_path":".env.example"}}' 0 "checks .env.example (exit 0)"
test_ex env-drift-guard.sh '{"tool_input":{"file_path":"config/.env.sample"}}' 0 "checks .env.sample (exit 0)"

# file-change-tracker.sh (PostToolUse — exit 0 always, logs to file)
test_ex file-change-tracker.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt","content":"hello"}}' 0 "logs Write operation (exit 0)"
test_ex file-change-tracker.sh '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt","old_string":"a","new_string":"b"}}' 0 "logs Edit operation (exit 0)"
test_ex file-change-tracker.sh '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0 "ignores non-Write/Edit tools"

# git-stash-before-danger.sh (PreToolUse — exit 0 always, auto-stashes)
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"git checkout feature"}}' 0 "acts on git checkout (exit 0)"
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"git reset --soft HEAD~1"}}' 0 "acts on git reset (exit 0)"
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"git status"}}' 0 "ignores non-risky git commands"
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-git commands"

# hardcoded-secret-detector.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/app.js","new_string":"const x = 42"}}' 0 "clean code OK (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/app.js","new_string":"api_key = \"abcdefghijklmnopqrstuvwxyz\""}}' 0 "warns on hardcoded API key (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/app.js","new_string":"AKIAIOSFODNN7EXAMPLE1"}}' 0 "warns on AWS key (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":".env.local","new_string":"SECRET=abc123"}}' 0 "skips .env files"

# hook-debug-wrapper.sh (wraps another hook — exit 0 with no args)
test_ex hook-debug-wrapper.sh '{"tool_input":{"command":"echo test"}}' 0 "exits 0 when no hook script arg"

# hook-permission-fixer.sh (SessionStart — exit 0 always)
test_ex hook-permission-fixer.sh '{}' 0 "runs at session start (exit 0)"
test_ex hook-permission-fixer.sh '{"session_id":"abc123"}' 0 "accepts session data (exit 0)"

# max-line-length-check.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex max-line-length-check.sh '{"tool_input":{"file_path":"/tmp/nonexistent-file-xyz.txt"}}' 0 "ignores nonexistent file"
test_ex max-line-length-check.sh '{"tool_input":{"file_path":""}}' 0 "ignores empty file path"
test_ex max-line-length-check.sh '{"tool_input":{}}' 0 "ignores missing file_path"

# no-git-amend-push.sh (PreToolUse — exit 0 always, warns on stderr)
test_ex no-git-amend-push.sh '{"tool_input":{"command":"git commit --amend -m \"fix\""}}' 0 "checks amend (exit 0, warns if pushed)"
test_ex no-git-amend-push.sh '{"tool_input":{"command":"git commit -m \"normal\""}}' 0 "ignores normal commit"
test_ex no-git-amend-push.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-git commands"

# no-secrets-in-logs.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex no-secrets-in-logs.sh '{"tool_result":"Build succeeded, all tests pass"}' 0 "clean output OK (exit 0)"
test_ex no-secrets-in-logs.sh '{"tool_result":"password=hunter2"}' 0 "warns on password in output (exit 0)"
test_ex no-secrets-in-logs.sh '{"tool_result":"api_key=sk_live_abc123"}' 0 "warns on api_key in output (exit 0)"
test_ex no-secrets-in-logs.sh '{"tool_result":"Bearer eyJhbGciOiJIUzI"}' 0 "warns on bearer token (exit 0)"

# node-version-guard.sh (PreToolUse — exit 0 always, warns on stderr)
test_ex node-version-guard.sh '{"tool_input":{"command":"npm install lodash"}}' 0 "checks npm commands (exit 0)"
test_ex node-version-guard.sh '{"tool_input":{"command":"node server.js"}}' 0 "checks node commands (exit 0)"
test_ex node-version-guard.sh '{"tool_input":{"command":"echo hello"}}' 0 "ignores non-node commands"
test_ex node-version-guard.sh '{"tool_input":{"command":"git status"}}' 0 "ignores git commands"

# output-secret-mask.sh (PostToolUse — exit 0 always, warns on stderr)
test_ex output-secret-mask.sh '{"tool_result":{"stdout":"hello world"}}' 0 "clean output OK (exit 0)"
test_ex output-secret-mask.sh '{"tool_result":{"stdout":"AKIAIOSFODNN7EXAMPLE1"}}' 0 "warns on AWS key in output (exit 0)"
test_ex output-secret-mask.sh '{"tool_result":{"stdout":"ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZab"}}' 0 "warns on GitHub token in output (exit 0)"
test_ex output-secret-mask.sh '{"tool_result":{"stdout":"sk-proj-abcdefghijklmnopqrstuvwx"}}' 0 "warns on OpenAI key in output (exit 0)"
