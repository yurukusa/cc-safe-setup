# --- auto-approve-build edge cases ---
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":"  npm run build"}}' 0 "auto-approve-build: leading whitespace npm build (allow)"
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":"npm run typecheck"}}' 0 "auto-approve-build: npm run typecheck approved"
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":"bun test"}}' 0 "auto-approve-build: bun test approved"
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":"npx build"}}' 0 "auto-approve-build: npx build approved"
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":"npm run deploy"}}' 0 "auto-approve-build: npm run deploy not matched (no approve output, still exit 0)"
test_ex auto-approve-build.sh '{"tool_name":"Read","tool_input":{"file_path":"x"}}' 0 "auto-approve-build: non-Bash tool skipped"
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "auto-approve-build: empty command exits 0"
test_ex auto-approve-build.sh '{"tool_name":"Bash","tool_input":{"command":"pnpm run ci"}}' 0 "auto-approve-build: pnpm run ci approved"

# --- auto-approve-cargo edge cases ---
test_ex auto-approve-cargo.sh '{"tool_input":{"command":"cargo bench"}}' 0 "auto-approve-cargo: cargo bench approved"
test_ex auto-approve-cargo.sh '{"tool_input":{"command":"cargo doc"}}' 0 "auto-approve-cargo: cargo doc approved"
test_ex auto-approve-cargo.sh '{"tool_input":{"command":"cargo clean"}}' 0 "auto-approve-cargo: cargo clean approved"
test_ex auto-approve-cargo.sh '{"tool_input":{"command":"cargo run --release"}}' 0 "auto-approve-cargo: cargo run with flags approved"
test_ex auto-approve-cargo.sh '{"tool_input":{"command":"cargo publish"}}' 0 "auto-approve-cargo: cargo publish not in allowlist (exit 0, no approve)"
test_ex auto-approve-cargo.sh '{"tool_input":{"command":"  cargo test"}}' 0 "auto-approve-cargo: leading whitespace cargo test"
test_ex auto-approve-cargo.sh '{"tool_input":{"command":""}}' 0 "auto-approve-cargo: empty command exits 0"

# --- auto-approve-go edge cases ---
test_ex auto-approve-go.sh '{"tool_input":{"command":"go mod tidy"}}' 0 "auto-approve-go: go mod subcommand approved"
test_ex auto-approve-go.sh '{"tool_input":{"command":"go generate ./..."}}' 0 "auto-approve-go: go generate approved"
test_ex auto-approve-go.sh '{"tool_input":{"command":"go install ./cmd/..."}}' 0 "auto-approve-go: go install approved"
test_ex auto-approve-go.sh '{"tool_input":{"command":"go clean"}}' 0 "auto-approve-go: go clean approved"
test_ex auto-approve-go.sh '{"tool_input":{"command":"go tool pprof"}}' 0 "auto-approve-go: go tool not in allowlist (exit 0, no approve)"
test_ex auto-approve-go.sh '{"tool_input":{"command":"  go test ./..."}}' 0 "auto-approve-go: leading whitespace"
test_ex auto-approve-go.sh '{"tool_input":{"command":""}}' 0 "auto-approve-go: empty command exits 0"

# --- auto-approve-make edge cases ---
test_ex auto-approve-make.sh '{"tool_input":{"command":"make all"}}' 0 "auto-approve-make: make all approved"
test_ex auto-approve-make.sh '{"tool_input":{"command":"make clean"}}' 0 "auto-approve-make: make clean approved"
test_ex auto-approve-make.sh '{"tool_input":{"command":"make install"}}' 0 "auto-approve-make: make install approved"
test_ex auto-approve-make.sh '{"tool_input":{"command":"make dev"}}' 0 "auto-approve-make: make dev approved"
test_ex auto-approve-make.sh '{"tool_input":{"command":"make deploy"}}' 0 "auto-approve-make: make deploy not in allowlist (exit 0, no approve)"
test_ex auto-approve-make.sh '{"tool_input":{"command":"  make test"}}' 0 "auto-approve-make: leading whitespace"
test_ex auto-approve-make.sh '{"tool_input":{"command":""}}' 0 "auto-approve-make: empty command exits 0"

# --- auto-approve-python edge cases ---
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pytest -x -v tests/"}}' 0 "auto-approve-python: pytest with flags approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"python -m unittest discover"}}' 0 "auto-approve-python: python -m unittest approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"black src/"}}' 0 "auto-approve-python: black formatter approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"isort ."}}' 0 "auto-approve-python: isort approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pylint src/"}}' 0 "auto-approve-python: pylint approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pyright ."}}' 0 "auto-approve-python: pyright approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pip list"}}' 0 "auto-approve-python: pip list read-only approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pip freeze"}}' 0 "auto-approve-python: pip freeze approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pip show requests"}}' 0 "auto-approve-python: pip show approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"python3 -m py_compile src/app.py"}}' 0 "auto-approve-python: py_compile approved"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":"pip install requests"}}' 0 "auto-approve-python: pip install not approved (exit 0, no approve)"
test_ex auto-approve-python.sh '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "auto-approve-python: empty command exits 0"

# --- auto-approve-ssh edge cases ---
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh deploy@10.0.0.1 uptime"}}' 0 "auto-approve-ssh: ssh with IP + uptime approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host whoami"}}' 0 "auto-approve-ssh: ssh whoami approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host hostname"}}' 0 "auto-approve-ssh: ssh hostname approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host df"}}' 0 "auto-approve-ssh: ssh df approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host free"}}' 0 "auto-approve-ssh: ssh free approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host date"}}' 0 "auto-approve-ssh: ssh date approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host rm -rf /"}}' 0 "auto-approve-ssh: ssh dangerous cmd not approved (exit 0, no approve)"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":"ssh user@host cat /etc/os-release"}}' 0 "auto-approve-ssh: ssh cat /etc/os-release approved"
test_ex auto-approve-ssh.sh '{"tool_name":"Bash","tool_input":{"command":""}}' 0 "auto-approve-ssh: empty command exits 0"

# --- auto-checkpoint edge cases ---
test_ex auto-checkpoint.sh '{"tool_name":"Edit","tool_input":{"file_path":"src/app.ts"}}' 0 "auto-checkpoint: Edit triggers checkpoint (exit 0)"
test_ex auto-checkpoint.sh '{"tool_name":"Write","tool_input":{"file_path":"new-file.js"}}' 0 "auto-checkpoint: Write triggers checkpoint (exit 0)"
test_ex auto-checkpoint.sh '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 0 "auto-checkpoint: Bash tool skipped (exit 0)"
test_ex auto-checkpoint.sh '{"tool_name":"Read","tool_input":{"file_path":"x"}}' 0 "auto-checkpoint: Read tool skipped (exit 0)"
test_ex auto-checkpoint.sh '{}' 0 "auto-checkpoint: empty input exits 0"

# --- auto-push-worktree edge cases ---
test_ex auto-push-worktree.sh '{}' 0 "auto-push-worktree: empty input exits 0 (not on worktree branch)"
test_ex auto-push-worktree.sh '{"tool_name":"Bash"}' 0 "auto-push-worktree: non-worktree branch exits 0"

# --- auto-snapshot edge cases ---
test_ex auto-snapshot.sh '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/cc-test-snapshot-edge.txt"}}' 0 "auto-snapshot: Edit on nonexistent file exits 0 (nothing to snapshot)"
test_ex auto-snapshot.sh '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' 0 "auto-snapshot: Bash tool skipped (exit 0)"
test_ex auto-snapshot.sh '{"tool_name":"Read","tool_input":{"file_path":"x.js"}}' 0 "auto-snapshot: Read tool skipped (exit 0)"
test_ex auto-snapshot.sh '{"tool_name":"Write","tool_input":{}}' 0 "auto-snapshot: Write with no file_path exits 0"
test_ex auto-snapshot.sh '{}' 0 "auto-snapshot: empty input exits 0"

# --- backup-before-refactor edge cases ---
test_ex backup-before-refactor.sh '{"tool_input":{"command":"git mv src/old.ts src/new.ts"}}' 0 "backup-before-refactor: git mv in src triggers stash (exit 0)"
test_ex backup-before-refactor.sh '{"tool_input":{"command":"git mv lib/utils.js lib/helpers.js"}}' 0 "backup-before-refactor: git mv in lib triggers stash (exit 0)"
test_ex backup-before-refactor.sh '{"tool_input":{"command":"git mv app/main.py app/entry.py"}}' 0 "backup-before-refactor: git mv in app triggers stash (exit 0)"
test_ex backup-before-refactor.sh '{"tool_input":{"command":"git mv docs/old.md docs/new.md"}}' 0 "backup-before-refactor: git mv outside src/lib/app skipped (exit 0)"
test_ex backup-before-refactor.sh '{"tool_input":{"command":"git status"}}' 0 "backup-before-refactor: non-mv git command skipped (exit 0)"
test_ex backup-before-refactor.sh '{"tool_input":{"command":""}}' 0 "backup-before-refactor: empty command exits 0"

# --- binary-file-guard edge cases ---
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"image.PNG","content":"data"}}' 0 "binary-file-guard: uppercase .PNG warns (exit 0, case-insensitive)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"doc.pdf","content":"data"}}' 0 "binary-file-guard: .pdf warns (exit 0)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"archive.tar","content":"data"}}' 0 "binary-file-guard: .tar warns (exit 0)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"module.wasm","content":"data"}}' 0 "binary-file-guard: .wasm warns (exit 0)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"lib.dylib","content":"data"}}' 0 "binary-file-guard: .dylib warns (exit 0)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"app.ts","content":"code"}}' 0 "binary-file-guard: .ts no warn (exit 0)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"Makefile","content":"all:"}}' 0 "binary-file-guard: no extension no warn (exit 0)"
test_ex binary-file-guard.sh '{"tool_name":"Write","tool_input":{}}' 0 "binary-file-guard: missing file_path exits 0"

# --- changelog-reminder edge cases ---
test_ex changelog-reminder.sh '{"tool_input":{"command":"npm version minor"}}' 0 "changelog-reminder: npm version minor triggers reminder (exit 0)"
test_ex changelog-reminder.sh '{"tool_input":{"command":"npm version patch"}}' 0 "changelog-reminder: npm version patch triggers reminder (exit 0)"
test_ex changelog-reminder.sh '{"tool_input":{"command":"cargo set-version 1.2.0"}}' 0 "changelog-reminder: cargo set-version triggers reminder (exit 0)"
test_ex changelog-reminder.sh '{"tool_input":{"command":"poetry version minor"}}' 0 "changelog-reminder: poetry version triggers reminder (exit 0)"
test_ex changelog-reminder.sh '{"tool_input":{"command":"bump2version minor"}}' 0 "changelog-reminder: bump2version triggers reminder (exit 0)"
test_ex changelog-reminder.sh '{"tool_input":{"command":"npm install"}}' 0 "changelog-reminder: non-version command no reminder (exit 0)"
test_ex changelog-reminder.sh '{"tool_input":{"command":""}}' 0 "changelog-reminder: empty command exits 0"

# --- check-error-class edge cases ---
test_ex check-error-class.sh '{"tool_input":{"new_string":"throw new Error(\"failed\")"}}' 0 "check-error-class: throw Error exits 0 (advisory only)"
test_ex check-error-class.sh '{"tool_input":{"new_string":"throw \"raw string\""}}' 0 "check-error-class: throw string exits 0 (advisory only)"
test_ex check-error-class.sh '{"tool_input":{"content":"throw {code: 500}"}}' 0 "check-error-class: throw object via content field exits 0"
test_ex check-error-class.sh '{"tool_input":{}}' 0 "check-error-class: empty content exits 0"
test_ex check-error-class.sh '{}' 0 "check-error-class: empty input exits 0"

# --- check-error-message edge cases ---
test_ex check-error-message.sh '{"tool_input":{"new_string":"throw new Error(\"error\")"}}' 0 "check-error-message: generic 'error' warns (exit 0)"
test_ex check-error-message.sh '{"tool_input":{"new_string":"throw new Error(\"Error\")"}}' 0 "check-error-message: generic 'Error' warns (exit 0)"
test_ex check-error-message.sh '{"tool_input":{"new_string":"throw new Error(\"something went wrong\")"}}' 0 "check-error-message: 'something went wrong' warns (exit 0)"
test_ex check-error-message.sh '{"tool_input":{"new_string":"throw new Error(\"Failed to parse config file\")"}}' 0 "check-error-message: specific message no warn (exit 0)"
test_ex check-error-message.sh '{"tool_input":{"new_string":"const x = 42"}}' 0 "check-error-message: no throw exits 0"
test_ex check-error-message.sh '{"tool_input":{"content":"throw new Error(\"error\")"}}' 0 "check-error-message: content field also checked (exit 0)"
test_ex check-error-message.sh '{"tool_input":{}}' 0 "check-error-message: empty content exits 0"

# --- check-null-check edge cases ---
test_ex check-null-check.sh '{"tool_input":{"new_string":"obj.property.method()"}}' 0 "check-null-check: deep chain exits 0 (advisory only)"
test_ex check-null-check.sh '{"tool_input":{"new_string":"obj?.property?.method()"}}' 0 "check-null-check: optional chaining exits 0 (advisory only)"
test_ex check-null-check.sh '{"tool_input":{"new_string":"if (obj) obj.method()"}}' 0 "check-null-check: guarded access exits 0"
test_ex check-null-check.sh '{"tool_input":{"content":"data.items[0].name"}}' 0 "check-null-check: content field deep access exits 0"
test_ex check-null-check.sh '{"tool_input":{}}' 0 "check-null-check: empty content exits 0"

# --- check-return-types edge cases ---
test_ex check-return-types.sh '{"tool_input":{"new_string":"function hello(name) {"}}' 0 "check-return-types: function without return type warns (exit 0)"
test_ex check-return-types.sh '{"tool_input":{"new_string":"function hello(name): string {"}}' 0 "check-return-types: function with return type no warn (exit 0)"
test_ex check-return-types.sh '{"tool_input":{"new_string":"const x = 42"}}' 0 "check-return-types: no function exits 0"
test_ex check-return-types.sh '{"tool_input":{"new_string":"function process(data) {\n  return data;"}}' 0 "check-return-types: multiline function without type warns (exit 0)"
test_ex check-return-types.sh '{"tool_input":{}}' 0 "check-return-types: empty content exits 0"

# --- check-test-naming edge cases ---
test_ex check-test-naming.sh '{"tool_input":{"new_string":"it(\"test something\", () => {"}}' 0 "check-test-naming: it('test ...') warns non-descriptive (exit 0)"
test_ex check-test-naming.sh '{"tool_input":{"new_string":"it(\"check value\", () => {"}}' 0 "check-test-naming: it('check ...') warns non-descriptive (exit 0)"
test_ex check-test-naming.sh '{"tool_input":{"new_string":"it(\"should work\", () => {"}}' 0 "check-test-naming: it('should ...') warns non-descriptive (exit 0)"
test_ex check-test-naming.sh '{"tool_input":{"new_string":"it(\"returns 404 when user not found\", () => {"}}' 0 "check-test-naming: descriptive name no warn (exit 0)"
test_ex check-test-naming.sh '{"tool_input":{"new_string":"it('"'"'test something'"'"', () => {"}}' 0 "check-test-naming: single-quoted test name warns (exit 0)"
test_ex check-test-naming.sh '{"tool_input":{"new_string":"describe(\"test suite\", () => {"}}' 0 "check-test-naming: describe not matched (exit 0)"
test_ex check-test-naming.sh '{"tool_input":{}}' 0 "check-test-naming: empty content exits 0"

# --- check-tls-version edge cases ---
test_ex check-tls-version.sh '{"tool_input":{"new_string":"minVersion: \"TLSv1\""}}' 0 "check-tls-version: TLSv1 warns weak (exit 0)"
test_ex check-tls-version.sh '{"tool_input":{"new_string":"protocol: SSLv3"}}' 0 "check-tls-version: SSLv3 warns weak (exit 0)"
test_ex check-tls-version.sh '{"tool_input":{"new_string":"minVersion: \"TLSv1.2\""}}' 0 "check-tls-version: TLSv1.2 no warn (exit 0, dot excluded by regex)"
test_ex check-tls-version.sh '{"tool_input":{"new_string":"minVersion: \"TLSv1.3\""}}' 0 "check-tls-version: TLSv1.3 no warn (exit 0)"
test_ex check-tls-version.sh '{"tool_input":{"new_string":"const port = 443"}}' 0 "check-tls-version: no TLS reference (exit 0)"
test_ex check-tls-version.sh '{"tool_input":{"content":"ssl_protocols SSLv3 TLSv1;"}}' 0 "check-tls-version: nginx-style config warns (exit 0)"
test_ex check-tls-version.sh '{"tool_input":{}}' 0 "check-tls-version: empty content exits 0"

# --- ci-skip-guard edge cases ---
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git commit -m \"fix: patch [skip ci]\""}}' 0 "ci-skip-guard: [skip ci] in message warns (exit 0)"
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git commit -m \"fix: patch [ci skip]\""}}' 0 "ci-skip-guard: [ci skip] variant warns (exit 0)"
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git commit -m \"fix: patch [no ci]\""}}' 0 "ci-skip-guard: [no ci] variant warns (exit 0)"
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git commit --no-verify -m \"quick fix\""}}' 0 "ci-skip-guard: --no-verify warns (exit 0)"
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git commit -m \"[SKIP CI] uppercase\""}}' 0 "ci-skip-guard: [SKIP CI] uppercase warns (case-insensitive, exit 0)"
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git commit -m \"normal fix\""}}' 0 "ci-skip-guard: normal commit no warn (exit 0)"
test_ex ci-skip-guard.sh '{"tool_input":{"command":"git status"}}' 0 "ci-skip-guard: non-commit command exits 0"
test_ex ci-skip-guard.sh '{"tool_input":{"command":""}}' 0 "ci-skip-guard: empty command exits 0"

# --- commit-scope-guard edge cases ---
test_ex commit-scope-guard.sh '{"tool_input":{"command":"git commit -m \"feat: add feature\""}}' 0 "commit-scope-guard: git commit checks staged count (exit 0)"
test_ex commit-scope-guard.sh '{"tool_input":{"command":"git status"}}' 0 "commit-scope-guard: non-commit skipped (exit 0)"
test_ex commit-scope-guard.sh '{"tool_input":{"command":"echo git commit"}}' 0 "commit-scope-guard: echo git commit skipped (exit 0)"
test_ex commit-scope-guard.sh '{"tool_input":{"command":"  git commit -m test"}}' 0 "commit-scope-guard: leading whitespace git commit (exit 0)"
test_ex commit-scope-guard.sh '{"tool_input":{"command":""}}' 0 "commit-scope-guard: empty command exits 0"

# --- compact-reminder edge cases ---
test_ex compact-reminder.sh '{}' 0 "compact-reminder: empty input increments counter (exit 0)"
test_ex compact-reminder.sh '{"tool_name":"Edit"}' 0 "compact-reminder: with tool_name exits 0"
test_ex compact-reminder.sh '{"some":"data"}' 0 "compact-reminder: arbitrary JSON exits 0"

# --- context-snapshot edge cases ---
test_ex context-snapshot.sh '{}' 0 "context-snapshot: empty input creates snapshot (exit 0)"
test_ex context-snapshot.sh '{"tool_name":"anything"}' 0 "context-snapshot: with tool_name exits 0"
test_ex context-snapshot.sh '' 0 "context-snapshot: empty string exits 0"

# --- cost-tracker edge cases ---
test_ex cost-tracker.sh '{"tool_input":{"command":"npm test"}}' 0 "cost-tracker: tracks tool call (exit 0)"
test_ex cost-tracker.sh '{"tool_name":"Edit","tool_input":{"file_path":"x.ts"}}' 0 "cost-tracker: Edit tool tracked (exit 0)"
test_ex cost-tracker.sh '{}' 0 "cost-tracker: empty input tracked (exit 0)"

# --- crontab-guard edge cases ---
test_ex crontab-guard.sh '{"tool_input":{"command":"crontab -r"}}' 0 "crontab-guard: crontab -r warns (exit 0)"
test_ex crontab-guard.sh '{"tool_input":{"command":"crontab -e"}}' 0 "crontab-guard: crontab -e warns (exit 0)"
test_ex crontab-guard.sh '{"tool_input":{"command":"crontab -l"}}' 0 "crontab-guard: crontab -l not matched by -r/-e/- pattern (exit 0)"
test_ex crontab-guard.sh '{"tool_input":{"command":"echo crontab -r"}}' 0 "crontab-guard: echo crontab not blocked (exit 0)"
test_ex crontab-guard.sh '{"tool_input":{"command":"cat /etc/crontab"}}' 0 "crontab-guard: cat crontab not matched (exit 0)"
test_ex crontab-guard.sh '{"tool_input":{"command":""}}' 0 "crontab-guard: empty command exits 0"
