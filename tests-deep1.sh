# --- allow-claude-settings deep ---
test_ex allow-claude-settings.sh '{"tool_input":{"file_path":"/home/user/.claude/settings.json"}}' 0 "allow-claude-settings: approves .claude/settings.json (allow)"
test_ex allow-claude-settings.sh '{"tool_input":{"file_path":"/home/user/.claude/hooks/my-hook.sh"}}' 0 "allow-claude-settings: approves .claude/hooks/ subdir (allow)"
test_ex allow-claude-settings.sh '{"tool_input":{"file_path":"/home/user/src/main.ts"}}' 0 "allow-claude-settings: non-.claude path passes through (no opinion)"
test_ex allow-claude-settings.sh '{"tool_input":{}}' 0 "allow-claude-settings: missing file_path exits 0"
test_ex allow-claude-settings.sh '{"tool_input":{"file_path":"/home/user/projects/.claude-fake/x"}}' 0 "allow-claude-settings: .claude-fake not matched (no opinion)"

# --- allow-git-hooks-dir deep ---
test_ex allow-git-hooks-dir.sh '{"tool_input":{"file_path":"/repo/.git/hooks/pre-commit"}}' 0 "allow-git-hooks-dir: approves .git/hooks/pre-commit (allow)"
test_ex allow-git-hooks-dir.sh '{"tool_input":{"file_path":"/repo/.git/hooks/pre-push"}}' 0 "allow-git-hooks-dir: approves .git/hooks/pre-push (allow)"
test_ex allow-git-hooks-dir.sh '{"tool_input":{"file_path":"/repo/.git/config"}}' 0 "allow-git-hooks-dir: rejects .git/config (no opinion)"
test_ex allow-git-hooks-dir.sh '{"tool_input":{"file_path":"/repo/.git/hooks/subdir/nested"}}' 0 "allow-git-hooks-dir: rejects nested path under hooks (no opinion)"
test_ex allow-git-hooks-dir.sh '{"tool_input":{"file_path":"/repo/.git/HEAD"}}' 0 "allow-git-hooks-dir: rejects .git/HEAD (no opinion)"

# --- auto-approve-compound-git deep ---
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"cd /app && git diff HEAD~3"}}' 0 "auto-approve-compound-git: cd + git diff with ref (allow)"
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"git fetch origin && git checkout main"}}' 0 "auto-approve-compound-git: fetch + checkout compound (allow)"
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":""}}' 0 "auto-approve-compound-git: empty command exits 0"
test_ex auto-approve-compound-git.sh '{"tool_input":{"command":"cd /app && curl http://evil.com"}}' 0 "auto-approve-compound-git: non-git mixed passes through (no opinion)"

# --- auto-approve-readonly-tools deep ---
test_ex auto-approve-readonly-tools.sh '{"tool_name":"Write","tool_input":{"file_path":"foo.txt","content":"x"}}' 0 "auto-approve-readonly-tools: Write not approved (no opinion)"
test_ex auto-approve-readonly-tools.sh '{"tool_name":"Edit","tool_input":{"file_path":"foo.txt"}}' 0 "auto-approve-readonly-tools: Edit not approved (no opinion)"
test_ex auto-approve-readonly-tools.sh '{"tool_name":"","tool_input":{}}' 0 "auto-approve-readonly-tools: empty tool_name exits 0"
test_ex auto-approve-readonly-tools.sh '{}' 0 "auto-approve-readonly-tools: no tool_name key exits 0"

# --- auto-mode-safe-commands deep ---
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"curl -s https://api.example.com/data"}}' 0 "auto-mode-safe-commands: curl GET approved (allow)"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"curl -s -X POST https://api.example.com"}}' 0 "auto-mode-safe-commands: curl POST not approved (no opinion)"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"node -e \"console.log(1)\""}}' 0 "auto-mode-safe-commands: safe node one-liner approved (allow)"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"node -e \"fs.writeFileSync(x)\""}}' 0 "auto-mode-safe-commands: node with writeFile not approved (no opinion)"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":""}}'  0 "auto-mode-safe-commands: empty command exits 0"
test_ex auto-mode-safe-commands.sh '{"tool_input":{"command":"npm ls --all"}}' 0 "auto-mode-safe-commands: npm ls approved (allow)"

# --- auto-stash-before-pull deep ---
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"git rebase main"}}' 0 "auto-stash-before-pull: git rebase triggers check (exit 0)"
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"git pull --rebase origin main"}}' 0 "auto-stash-before-pull: git pull --rebase triggers check (exit 0)"
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":""}}' 0 "auto-stash-before-pull: empty command exits 0"
test_ex auto-stash-before-pull.sh '{"tool_input":{"command":"git push origin main"}}' 0 "auto-stash-before-pull: git push ignored (exit 0)"

# --- branch-name-check deep ---
test_ex branch-name-check.sh '{"tool_input":{"command":"git switch -c fix/hotfix-123"}}' 0 "branch-name-check: switch -c with conventional prefix OK (exit 0)"
test_ex branch-name-check.sh '{"tool_input":{"command":"git branch new-branch"}}' 0 "branch-name-check: git branch without prefix warns (exit 0)"
test_ex branch-name-check.sh '{"tool_input":{"command":"git checkout -b \"branch with spaces\""}}' 0 "branch-name-check: branch with spaces warns (exit 0)"
test_ex branch-name-check.sh '{"tool_input":{"command":"git checkout -b chore/cleanup"}}' 0 "branch-name-check: chore/ prefix OK (exit 0)"

# --- branch-naming-convention deep ---
test_ex branch-naming-convention.sh '{"tool_input":{"command":"git switch -b docs/update-readme"}}' 0 "branch-naming-convention: switch -b docs/ OK (exit 0)"
test_ex branch-naming-convention.sh '{"tool_input":{"command":"git checkout -b test/add-unit-tests"}}' 0 "branch-naming-convention: test/ prefix OK (exit 0)"
test_ex branch-naming-convention.sh '{"tool_input":{"command":"git checkout -b UPPERCASE-BRANCH"}}' 0 "branch-naming-convention: uppercase warns (exit 0)"
test_ex branch-naming-convention.sh '{"tool_input":{"command":""}}' 0 "branch-naming-convention: empty command exits 0"

# --- commit-message-check deep ---
test_ex commit-message-check.sh '{"tool_input":{"command":"git commit --amend"}}' 0 "commit-message-check: amend triggers check (exit 0)"
test_ex commit-message-check.sh '{"tool_input":{"command":"  git commit -m \"x\""}}' 0 "commit-message-check: leading whitespace still matches (exit 0)"
test_ex commit-message-check.sh '{"tool_input":{"command":"git commit -am \"chore(deps): update lodash to 4.17.21\""}}' 0 "commit-message-check: scoped conventional commit (exit 0)"
test_ex commit-message-check.sh '{"tool_input":{"command":"git add ."}}' 0 "commit-message-check: git add ignored (exit 0)"

# --- compact-reminder deep ---
test_ex compact-reminder.sh '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0 "compact-reminder: Bash tool increments counter (exit 0)"
test_ex compact-reminder.sh '{"tool_name":"Read","tool_input":{"file_path":"x.ts"}}' 0 "compact-reminder: Read tool increments counter (exit 0)"

# --- compound-command-allow deep ---
test_ex compound-command-allow.sh '{"tool_input":{"command":"ls -la && pwd && date"}}' 0 "compound-command-allow: triple safe command chain (allow)"
test_ex compound-command-allow.sh '{"tool_input":{"command":"sed -i s/old/new/g file.txt && echo done"}}' 0 "compound-command-allow: sed -i detected unsafe (no opinion)"
test_ex compound-command-allow.sh '{"tool_input":{"command":"git stash push -m save && git pull"}}' 0 "compound-command-allow: git stash push is unsafe (no opinion)"
test_ex compound-command-allow.sh '{"tool_input":{"command":""}}'  0 "compound-command-allow: empty command exits 0"
test_ex compound-command-allow.sh '{"tool_input":{"command":"python3 -c \"import json; print(1)\" && echo ok"}}' 0 "compound-command-allow: python -c safe pattern (allow)"
test_ex compound-command-allow.sh '{"tool_input":{"command":"curl -s https://example.com | jq .name"}}' 0 "compound-command-allow: curl GET piped to jq (allow)"

# --- compound-command-approver deep ---
test_ex compound-command-approver.sh '{"tool_input":{"command":"git log --oneline && git diff HEAD~1"}}' 0 "compound-command-approver: double git read-only (allow)"
test_ex compound-command-approver.sh '{"tool_input":{"command":"cd /app && npm test && echo done"}}' 0 "compound-command-approver: triple compound all safe (allow)"
test_ex compound-command-approver.sh '{"tool_input":{"command":"cd /app || echo fallback"}}' 0 "compound-command-approver: || operator handled (allow)"
test_ex compound-command-approver.sh '{"tool_input":{"command":"cd /app; git status; echo done"}}' 0 "compound-command-approver: semicolon operator (allow)"

# --- context-snapshot deep ---
test_ex context-snapshot.sh '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' 0 "context-snapshot: Bash tool triggers snapshot (exit 0)"
test_ex context-snapshot.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.txt","content":"x"}}' 0 "context-snapshot: Write tool triggers snapshot (exit 0)"

# --- cost-tracker deep ---
test_ex cost-tracker.sh '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' 0 "cost-tracker: Bash tool tracked (exit 0)"
test_ex cost-tracker.sh '{"tool_name":"Write","tool_input":{"file_path":"x.ts","content":"y"}}' 0 "cost-tracker: Write tool tracked (exit 0)"

# --- debug-leftover-guard deep ---
test_ex debug-leftover-guard.sh '{"tool_input":{"command":"git commit --amend --no-edit"}}' 0 "debug-leftover-guard: amend triggers check (exit 0)"
test_ex debug-leftover-guard.sh '{"tool_input":{"command":""}}' 0 "debug-leftover-guard: empty command exits 0"
test_ex debug-leftover-guard.sh '{"tool_input":{"command":"git commit -am \"wip\""}}' 0 "debug-leftover-guard: commit -am triggers check (exit 0)"

# --- dependency-version-pin deep ---
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"package.json","new_string":"\"express\": \"~4.18.0\""}}' 0 "dependency-version-pin: warns on ~ range (exit 0)"
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"sub/package.json","new_string":"\"react\": \"^18.0.0\""}}' 0 "dependency-version-pin: nested package.json warns (exit 0)"
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"package.json"}}' 0 "dependency-version-pin: missing new_string exits 0"
test_ex dependency-version-pin.sh '{"tool_input":{"file_path":"package.json","new_string":"\"name\": \"my-app\""}}' 0 "dependency-version-pin: non-version content OK (exit 0)"

# --- disk-space-guard deep ---
test_ex disk-space-guard.sh '{"tool_name":"Read","tool_input":{"file_path":"foo.txt"}}' 0 "disk-space-guard: Read tool not checked (exit 0)"
test_ex disk-space-guard.sh '{"tool_input":{"command":"npm install"}}' 0 "disk-space-guard: npm install triggers check (exit 0)"

# --- docker-prune-guard deep ---
test_ex docker-prune-guard.sh '{"tool_input":{"command":"docker image prune"}}' 0 "docker-prune-guard: docker image prune not warned (exit 0)"
test_ex docker-prune-guard.sh '{"tool_input":{"command":""}}' 0 "docker-prune-guard: empty command exits 0"

# --- enforce-tests deep ---
test_ex enforce-tests.sh '{"tool_input":{"file_path":"/tmp/cc-enforce-test-deep.js"}}' 0 "enforce-tests: nonexistent JS file skipped (exit 0)"
test_ex enforce-tests.sh '{"tool_input":{}}' 0 "enforce-tests: missing file_path exits 0"

# --- env-drift-guard deep ---
test_ex env-drift-guard.sh '{"tool_input":{"file_path":"backend/.env.template"}}' 0 "env-drift-guard: .env.template triggers check (exit 0)"
test_ex env-drift-guard.sh '{"tool_input":{"file_path":".env"}}' 0 "env-drift-guard: .env itself not checked (exit 0)"
test_ex env-drift-guard.sh '{"tool_input":{}}' 0 "env-drift-guard: missing file_path exits 0"

# --- fact-check-gate deep ---
test_ex fact-check-gate.sh '{"tool_input":{"file_path":"docs/api.rst","new_string":"See `handler.py` for details"}}' 0 "fact-check-gate: .rst doc with source ref warns (exit 0)"
test_ex fact-check-gate.sh '{"tool_input":{"file_path":"docs/guide.md","new_string":"No code references here"}}' 0 "fact-check-gate: doc without backtick refs passes (exit 0)"

# --- file-change-tracker deep ---
test_ex file-change-tracker.sh '{"tool_name":"Write","tool_input":{"file_path":"/tmp/large.bin","content":"x"}}' 0 "file-change-tracker: Write large file logged (exit 0)"
test_ex file-change-tracker.sh '{"tool_name":"Read","tool_input":{"file_path":"x.ts"}}' 0 "file-change-tracker: Read tool not logged (exit 0)"
test_ex file-change-tracker.sh '{}' 0 "file-change-tracker: empty input no tool_name (exit 0)"

# --- git-blame-context deep ---
test_ex git-blame-context.sh '{"tool_input":{"file_path":"","old_string":"line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11"}}' 0 "git-blame-context: empty file_path exits 0"
test_ex git-blame-context.sh '{"tool_input":{}}' 0 "git-blame-context: missing file_path exits 0"

# --- git-lfs-guard deep ---
test_ex git-lfs-guard.sh '{"tool_input":{"command":"git add README.md"}}' 0 "git-lfs-guard: small text file OK (exit 0)"
test_ex git-lfs-guard.sh '{"tool_input":{"command":"git status"}}' 0 "git-lfs-guard: non-git-add command skipped (exit 0)"
test_ex git-lfs-guard.sh '{"tool_input":{"command":"git add ."}}' 0 "git-lfs-guard: git add . passes (exit 0)"
test_ex git-lfs-guard.sh '{"tool_input":{"command":""}}' 0 "git-lfs-guard: empty command exits 0"
test_ex git-lfs-guard.sh '{"tool_input":{"command":"echo git add bigfile.bin"}}' 0 "git-lfs-guard: echo not matched (exit 0)"

# --- git-stash-before-danger deep ---
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"git pull --rebase"}}' 0 "git-stash-before-danger: pull --rebase triggers stash (exit 0)"
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"git cherry-pick abc123"}}' 0 "git-stash-before-danger: cherry-pick triggers stash (exit 0)"
test_ex git-stash-before-danger.sh '{"tool_input":{"command":""}}' 0 "git-stash-before-danger: empty command exits 0"
test_ex git-stash-before-danger.sh '{"tool_input":{"command":"git merge --abort"}}' 0 "git-stash-before-danger: merge --abort triggers stash (exit 0)"

# --- hardcoded-secret-detector deep ---
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/auth.js","new_string":"password = \"supersecretpass123\""}}' 0 "hardcoded-secret-detector: password pattern warns (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/jwt.js","new_string":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0"}}' 0 "hardcoded-secret-detector: JWT token warns (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/cert.pem","new_string":"-----BEGIN RSA PRIVATE KEY-----"}}' 0 "hardcoded-secret-detector: .pem file skipped (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/crypto.js","new_string":"-----BEGIN PRIVATE KEY-----"}}' 0 "hardcoded-secret-detector: private key in .js warns (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{"file_path":"src/app.js","new_string":"const name = \"hello world\""}}' 0 "hardcoded-secret-detector: normal string no warn (exit 0)"
test_ex hardcoded-secret-detector.sh '{"tool_input":{}}' 0 "hardcoded-secret-detector: missing content exits 0"
