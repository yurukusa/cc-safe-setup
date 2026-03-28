# Changelog

## [29.6.28] - 2026-03-29
- **New**: 4 hooks — credential-file-cat-guard (#34819), push-requires-test-pass (#36673), push-requires-test-pass-record, edit-retry-loop-guard (#35576)
- **New**: 3 SEO pages — auto-approve-guide, prevent-credential-leak, owasp-mcp-hooks
- **Docs**: COOKBOOK recipes for credential guard and push-requires-test
- **Docs**: examples/README overhaul (38→511), Japanese README overhaul (36→511)
- **Tests**: 36 new tests for new hooks
- **Tests**: Trigger detection tests (verify PermissionRequest/SessionStart/PreToolUse parsing)
- **Stats**: 514 examples, 7,564 tests, 51 SEO pages

## [29.6.0] - 2026-03-27
- **Improved**: worktree-unmerged-guard — python3 fallback for macOS (no jq dependency), auto-detect default branch
- **Fix**: CI workflow — add git config for tests that require commits
- **Stats**: 347 examples, 2,352 tests

## [29.5.0] - 2026-03-26
- **New**: 3 hooks invented and released — auto-mode-safe-commands, write-secret-guard, compound-command-allow
- **New**: 10 example hooks — credential-exfil-guard, rm-safety-net, worktree-unmerged-guard, permission-audit-log, session-token-counter, file-change-tracker, output-secret-mask + 3 more
- **New**: 5 hooks — git-stash-before-danger, session-summary-stop, max-edit-size-guard, auto-approve-readonly-tools, uncommitted-changes-stop
- **Tests**: 2,352 tests (up from 1,062)
- **Stats**: 348 examples

## [29.4.0] - 2026-03-26
- **Tests**: 32 new tests for 10 example hooks (scope-guard, git-config-guard, path-traversal-guard, env-var-check, auto-approve-readonly/git-read/build/python, block-database-wipe, deploy-guard, network-guard)
- **Fix**: --doctor now checks all 9 hook trigger types
- **Stats**: 1062 tests (up from 1030)

## [29.3.0] - 2026-03-26
- **Fix**: Unified trigger detection with regex (case-insensitive `Trigger:` / `TRIGGER:`)
- Previously, hooks with `# Trigger: X` (capitalized) would not be detected by --install-example

## [29.2.0] - 2026-03-26
- **New**: UserPromptSubmit hook examples (prompt-length-guard, prompt-injection-detector)
- **Fix**: --install-example now detects UserPromptSubmit trigger
- **Fix**: Case-insensitive trigger detection (Trigger: vs TRIGGER:)
- **Stats**: 338 examples, 1030 tests

## [29.1.0] - 2026-03-26
- **Tests**: Trigger detection tests (verify PermissionRequest/SessionStart/PreToolUse parsing)
- **Stats**: 1024 tests (2^10 milestone!)

## [29.0.0] - 2026-03-26
- **BREAKING**: `--install-example` now correctly detects PermissionRequest trigger and comment-style matchers
- Previously, PermissionRequest hooks were silently registered as PreToolUse (wrong trigger!)
- Comment-style `# Matcher: Edit|Write` headers now parsed (previously only JSON format)
- All 4 new PermissionRequest examples install correctly with proper trigger and matcher

## [28.9.0] - 2026-03-26
- **New**: 4 PermissionRequest hooks now discoverable via `--examples permission`
- **Docs**: hook-patterns.html — PermissionRequest pattern with copy-paste code
- **Fix**: --examples category list updated (136 discoverable, 336 total)

## [28.8.0] - 2026-03-26
- **New**: auto-approve-compound-git.sh — PermissionRequest hook for compound git commands (#30519)
- **Fix**: Example count corrected to 336 (was underreported)
- **Fix**: Draft factcheck — code examples now match actual hook files
- **Stats**: 336 examples, 1018 tests

## [28.7.0] - 2026-03-26
- **New examples**: allow-claude-settings.sh, allow-protected-dirs.sh (PermissionRequest)
- **Docs**: TROUBLESHOOTING — Stop hook `-p` empty output known issue (#38651)
- **Stats**: 333 examples, 1009 tests (1000+ milestone!)

## [28.6.0] - 2026-03-26
- **New**: PermissionRequest hook support — `allow-git-hooks-dir.sh` example (first PermissionRequest example)
- **Docs**: Hook execution order documented (PreToolUse → built-in checks → PermissionRequest)
- **Docs**: TROUBLESHOOTING.md — new section "PreToolUse allow doesn't bypass protected directory prompts"
- **Docs**: COOKBOOK.md — Recipe #27: Bypass Protected Directory Prompts
- **Stats**: 331 examples, 996 tests, 49 commands, 23 web tools

## [28.4.9] - 2026-03-26
- **Bug fix**: --rules YAML template regex escaping (\\s → \s for grep whitespace matching)
- **Bug fix**: Windows path backslash in --shield, --guard, --rules, --protect (#1)
- **Bug fix**: Add missing shebangs to 145 example hooks
- **New hooks**: hook-permission-fixer (auto-fix +x at session start), response-budget-guard (anti-loop)
- **New web tool**: Permission Checker (23rd) — diagnose broken paths, Windows issues
- **--doctor**: Now detects Windows backslash paths in hook commands
- **--audit**: New checks for Windows paths (CRITICAL) and missing permission fixer (LOW)
- **COOKBOOK.md**: 26 practical recipes for common scenarios
- **Windows Support**: README section added with diagnosis guide
- **Docs**: Ops Kit CTA on 7 pages (getting-started, hub, recipes, playground, validator, cheatsheet, faq)
- **Stats**: 330 examples, 988 tests, 49 commands, 23 web tools
- **Issue answers**: anthropics/claude-code #38901, #38923; cc-safe-setup #1
- **npm**: 10,143 downloads/day

## [28.3.5] - 2026-03-25
- **327 HOOKS** (314 bash + 5 non-bash + 8 built-in), **955 tests**
- New hooks: skill-gate, auto-approve-test, no-push-without-ci, no-commit-fixup, no-large-commit, no-sleep-in-hooks, check-git-hooks-compat
- --shield now auto-installs memory-write-guard, skill-gate, auto-approve-test, auto-approve-readonly
- 227 hooks in web registry
- Issue answers: #38040 (memory permission gap), #37988 (Windows hook timeout), #37913 (permission timeout)
- GitHub profile README created (https://github.com/yurukusa/yurukusa)
- Ops Kit LP updated (8K downloads/week, correct Gumroad slug)

## [28.1.0] - 2026-03-25
- **305 HOOKS** — 244 new hooks in session 40 (61→305)
- 210 hooks in web registry
- Session 40 stats: 68 npm releases, 9 OSS PRs, 15 issue answers, 25 articles

## [28.0.0] - 2026-03-25
- **300 HOOKS** — 239 new hooks in one session (61→300)
- 40 React/JS/performance hooks, 15 OWASP security hooks, 10 a11y hooks
- 45 CLI commands, 561 tests, 5 languages, 11 web tools
- 200 hooks in registry, 25 articles, 67 npm releases

## [26.0.0] - 2026-03-25
- **250 HOOKS** — 189 new hooks in one session (61→250)
- 15 OWASP security hooks (injection, XSS, auth, TLS, CORS, CSP)
- 200 hooks in web registry, 45 commands, 561 tests
- 24 articles (5 published), 65 npm releases

## [22.0.0] - 2026-03-25
- **200 HOOKS MILESTONE** — 139 new hooks in one session (61→200)
- 45 CLI commands, 561 tests, 5 languages, 11 web tools, 140 registry hooks
- 9 OSS PRs (3,755★), 14 issue answers, 23 articles, 11 Zenn Book chapters
- Quality hooks: no-var, prefer-const, no-any-type, no-nested-ternary, no-sync-fs
- Security hooks: sql-injection-detect, cors-star-warn, no-http-without-https
- Code review hooks: max-function-length, no-deep-nesting, no-empty-function

## [17.4.0] - 2026-03-25
- **165 hooks** (+104 from session start), **45 CLI commands**, **561 tests**
- --changelog, --init-project, --score, --test-hook, --save-profile, --guard, --suggest, --why, --replay, --from-claudemd, --team, --profile, --analyze, --health, --quickfix, --migrate-from, --diff-hooks, --shield
- 11 web tools (+ Setup Wizard), 123 registry hooks
- 9 OSS PRs (3,755★), 14 issue answers, 22 articles, 11 Zenn Book chapters
- CDP dialog polling fix, npm 40% smaller
- 104 new hooks in one session — the largest single-session expansion ever

## [14.1.0] - 2026-03-25
- **141 hooks**, **44 CLI commands**, **561 tests**, **5 languages**, **11 web tools**
- --init-project, --score, --test-hook, --save-profile
- Setup Wizard, 104 registry hooks, 9 OSS PRs (3,755★), 12 issue answers
- CDP dialog polling fix, npm 40% smaller, Zenn Book Ch9-10
- 21 new hooks: relative-path, encoding, ssh-key, terraform, k8s, subagent-scope, etc.

## [11.0.0] - 2026-03-24
- **--suggest**: Predictive risk analysis (git history, files, deps, config)
- **--why**: Show real incident behind each hook (20 documented)
- **--replay**: Visual blocked commands timeline
- **--guard**: Instant rule enforcement from plain English
- **--diff-hooks**: Compare hook configurations
- **120 hooks**, **40 CLI commands**, **544 tests**, **5 languages**
- 10 web tools + Hub, 80 registry hooks
- OSS: 4 PRs to 3 repos (3,255★ combined)
- CDP dialog polling fix (WSL2 root cause)
- typosquat-guard, test-coverage-guard, stale-env-guard, permission-cache, git-author-guard, typescript-strict-guard, ci-skip-guard, debug-leftover-guard
- 14 article drafts (10 cron, 3 CDP pending)

## [10.3.0] - 2026-03-24
- **--guard**: Instant rule enforcement — `--guard "never touch the database"`
- **--diff-hooks**: Compare global vs project hook configurations
- **531 tests** (500+ milestone), **116 hooks**, **37 CLI commands**, **5 languages**
- test-coverage-guard, stale-env-guard, ci-skip-guard, debug-leftover-guard
- Rust destructive-guard example
- 10 web tools + Hub portal + By Example + Migration Guide + Troubleshooting + Matrix + Settings Reference
- 13 article drafts (1 published, 9 cron, 3 CDP-pending)
- Medium story draft for maximum reach

## [10.0.0] - 2026-03-24
- 500+ test milestone, fixed test ordering

## [9.3.0] - 2026-03-24
- **--from-claudemd**: Convert CLAUDE.md rules to enforceable hooks (16 patterns)
- **--health**: Hook health dashboard (size, permissions, age)
- **--migrate-from**: Migrate from safety-net/hooks-mastery/manual
- **Rust** destructive-guard example (5 languages)
- **10 web tools**: Hub, Matrix, Troubleshooting, Settings Reference, By Example, Migration, Builder, FAQ, Cheat Sheet, Playground
- **114 hooks** (106 bash + 2 Python + 1 Go + 1 TypeScript + 1 Rust + 3 new)
- **35 CLI commands**, **457 tests**
- ci-skip-guard, debug-leftover-guard, env-drift-guard, package-script-guard, git-blame-context, import-cycle-warn, docker-prune-guard, node-version-guard, pip-venv-guard, no-git-amend-push, sensitive-regex-guard, lockfile-guard, git-lfs-guard, context-snapshot

## [9.1.0] - 2026-03-24
- Improved --generate-ci (npx-based, actually works)

## [9.0.0] - 2026-03-24
- 112 hooks, 34 commands, 8 web tools

## [8.4.0] - 2026-03-24
- **--team**: Project-level hook sharing (relative paths, git-committable)
- **--analyze**: Session analysis (blocked commands, git activity, costs)
- **--profile**: Safety profiles (strict/standard/minimal)
- **32 CLI commands**, **457 tests**, **100 hooks**
- 24 new tests for newest hooks batch
- 7 article drafts with cron pipelines (3/28-4/2)

## [8.3.0] - 2026-03-24
- **--profile**: Switch safety profiles (strict/standard/minimal)
- **--analyze**: See what Claude did in sessions (blocked commands, git activity, costs)
- **100 HOOKS milestone** (92 examples + 8 built-in)
- 10 new hooks: no-console-log, backup-before-refactor, rate-limit-guard, file-size-limit, no-eval, branch-naming-convention, pr-description-check, no-wildcard-import, no-todo-ship, license-check
- hardcoded-secret-detector, changelog-reminder
- **31 CLI commands**, **433 tests**

## [8.1.0] - 2026-03-24
- 100 hooks milestone

## [8.0.0] - 2026-03-24
- **--shield**: Maximum safety in one command (fix + scan + install + CLAUDE.md)
- **88 hooks** (8 built-in + 80 examples), **433 tests**, **29 commands**
- worktree-guard, commit-scope-guard, compact-reminder, auto-stash-before-pull, revert-helper
- Hook Builder web tool (generate from plain English)
- FAQ page (15 questions answered)
- 5 web tools total (Audit, Cheat Sheet, Builder, FAQ, Playground)

## [7.9.0] - 2026-03-24
- Hook Builder and FAQ web tools
- Zenn tutorial published

## [7.8.0] - 2026-03-24
- revert-helper Stop hook
- OSS: PR #40 to disler/multi-agent-observability (1,295★)

## [7.7.0] - 2026-03-24
- **420 automated tests**, **83 hooks** (8 built-in + 75 examples)
- **error-memory-guard**: Block retries of commands that already failed 3x
- **parallel-edit-guard**: Detect concurrent edits via lock files
- **large-read-guard**: Warn before catting large files into context
- **strict-allowlist**: Allowlist-only enforcement mode (#37471)
- Gumroad Ops Kit updated to v3.2 via CDP (self-service)

## [7.6.0] - 2026-03-24
- strict-allowlist hook added
- 72 examples, 409 tests

## [7.5.0] - 2026-03-24
- **405 automated tests** (400+ milestone)
- **71 example hooks** (68→71: fact-check-gate, token-budget-guard, conflict-marker-guard)
- Hooks Cheat Sheet (copy-paste patterns, 30+ recipes)
- GitHub Issue answers with hook code (#37888, #38050, #38057)

## [7.4.0] - 2026-03-24
- **uncommitted-work-guard**: Block destructive git with uncommitted changes (#37888)
- **test-deletion-guard**: Warn when removing test assertions (#38050)
- **overwrite-guard**: Warn before silently overwriting files (#37595)
- **memory-write-guard**: Log writes to ~/.claude/ directory (#38040)
- 68 example hooks, 394 tests

## [7.3.0] - 2026-03-24
- **--quickfix**: Auto-detect and fix 10 common Claude Code problems
- **367 automated tests** (+47 from v7.2.0, full example hook coverage)
- **28 CLI commands** total
- Hook Playground web tool (interactive command safety checker)
- Beginner tutorial drafts (EN + JP)

## [7.2.0] - 2026-03-24
- **71 total hooks** (8 built-in + 61 bash + 2 Python)
- **27 CLI commands** including --report, --generate-ci, --migrate, --compare, --issues
- **318 automated tests** (+145 from session start)
- Python hook examples (destructive_guard.py, secret_guard.py)
- Unified SPA web tool (audit + builder + cookbook + ecosystem + cheat sheet)
- New hooks: no-deploy-friday, work-hours-guard, protect-claudemd, reinject-claudemd,
  symlink-guard, env-source-guard, no-sudo-guard, no-install-global, git-tag-guard,
  npm-publish-guard, auto-approve-{go,cargo,make,gradle,maven}, output-length-guard
- 15 example hooks with individual functional tests

## [3.7.0] - 2026-03-24
- **--benchmark**: Hook performance measurement (10 runs, color-coded)
- dependency-audit.sh, diff-size-guard.sh, commit-quality-gate.sh
- session-handoff.sh, loop-detector.sh, hook-debug-wrapper.sh
- Japanese README (docs/README.ja.md)
- CI: example hooks syntax check (36/36)
- 21 commands, 36 examples, 173 tests

## [3.4.0] - 2026-03-24
- **--diff**: Compare settings between environments
- **--share**: Generate shareable audit URL
- **--lint**: Static analysis of hook configuration
- **--create**: Natural language hook generator (9 templates)
- TROUBLESHOOTING.md, SETTINGS_REFERENCE.md, MIGRATION.md
- Cheat Sheet, Ecosystem comparison page
- Web: setup generator + URL import

## [3.0.0] - 2026-03-24
- **--doctor**: Diagnose hook issues (jq, permissions, shebang)
- **--watch**: Live blocked command dashboard
- **--stats**: Block history analytics
- **--export/--import**: Team hook sharing
- **--audit --json**: CI output with threshold support
- case-sensitive-guard.sh (#37875), compound-command-approver.sh (#30519)
- tmp-cleanup.sh (#8856), GitHub Action outputs

## [2.0.6] - 2026-03-23
- **9 new examples**: deploy-guard, network-guard, test-before-push, large-file-guard, commit-message-check, env-var-check, timeout-guard, branch-name-check, path-traversal-guard, todo-check
- Tests: 138 → 154
- 25 examples total (was 19 in v2.0.0)
- Categories: Safety Guards (12), Auto-Approve (5), Quality (6), Recovery (2), UX (1)

## [2.0.0] - 2026-03-23
- **Categorized `--examples` output** — 5 categories: Safety Guards, Auto-Approve, Quality, Recovery, UX
- **New examples: deploy-guard, network-guard, test-before-push, large-file-guard** (4 new)
- 19 examples total (was 15)
- Tests: 130 → 138

## [1.9.4] - 2026-03-23
- **New example: deploy-guard.sh** — blocks deploy commands when uncommitted changes exist
- Detects rsync, scp, firebase, vercel, netlify, fly, heroku
- Born from [#37314](https://github.com/anthropics/claude-code/issues/37314) (deploy without commit)
- Tests: 126 → 130
- 16 examples total (was 15)

## [1.9.3] - 2026-03-23
- **New example: git-config-guard.sh** — blocks git config --global modifications without consent
- Born from [#37201](https://github.com/anthropics/claude-code/issues/37201) (unauthorized git config changes)
- CLI smoke tests added (--help, --examples, --install-example)
- Tests: 119 → 126
- 15 examples total (was 14)

## [1.9.2] - 2026-03-23
- **`--status` now detects installed example hooks** — shows which examples are active alongside the 8 built-in hooks
- CLI incidents list: added PowerShell Remove-Item and Prisma migrate reset

## [1.9.1] - 2026-03-23
- **New example: auto-checkpoint.sh** — auto-commit after every edit for rollback protection
- Born from [#34674](https://github.com/anthropics/claude-code/issues/34674) (context compaction reverting uncommitted edits)
- Tests: 116 → 119
- 14 examples total (was 13)

## [1.9.0] - 2026-03-23
- **New `--install-example` flag** — install any example hook with one command
  - `npx cc-safe-setup --install-example block-database-wipe`
  - Copies hook to `~/.claude/hooks/`, adds to `settings.json`, makes executable
  - Auto-detects trigger (PreToolUse/PostToolUse/etc.) and matcher from hook header

## [1.8.4] - 2026-03-23
- **New example: scope-guard.sh** — blocks file operations outside project directory (absolute paths, home dir, parent escapes)
- Born from [#36233](https://github.com/anthropics/claude-code/issues/36233) (entire Mac filesystem deleted)
- Tests: 99 → 106
- 13 examples total (was 12)

## [1.8.3] - 2026-03-23
- **New example: protect-dotfiles.sh** — blocks modifications to ~/.bashrc, ~/.aws/, ~/.ssh/ and chezmoi without diff
- **New example: allowlist.sh** added to --examples index
- Born from [#37478](https://github.com/anthropics/claude-code/issues/37478) (environment file destruction)
- Tests: 90 → 99
- 12 examples total (was 10)

## [1.8.2] - 2026-03-22
- **New example: auto-snapshot.sh** — automatic file snapshots before edits for rollback protection
- **New example: auto-approve-python.sh** — auto-approve pytest, mypy, ruff, black, isort
- 10 examples total (was 8)

## [1.8.0] - 2026-03-22
- **New `--examples` flag** — lists all 8 example hooks with descriptions from the CLI
- **New example: block-database-wipe.sh** — blocks destructive database commands (Laravel, Django, Rails, raw SQL)
- Born from [#37405](https://github.com/anthropics/claude-code/issues/37405) and [#37439](https://github.com/anthropics/claude-code/issues/37439)

## [1.7.2] - 2026-03-22
- **Fix: echo/printf/cat false positives** — string output commands mentioning PowerShell patterns no longer blocked
- Tests: 89 → 90

## [1.7.1] - 2026-03-22
- **Fix: git commit message false positive** — commit messages containing PowerShell command text no longer blocked
- Restored git checkout/switch --force check
- Tests: 88 → 89

## [1.7.0] - 2026-03-22
- **PowerShell destructive command protection** — blocks `Remove-Item -Recurse -Force`, `rd /s /q`, `del /s /q`
- Born from [#37331](https://github.com/anthropics/claude-code/issues/37331): Claude ran `Remove-Item -Recurse -Force *` destroying all unpushed source code
- Tests: 82 → 88

## [1.6.5] - 2026-03-22
- Security fix: `sudo mkfs` now blocked
- WSL2: `/mnt` paths now blocked for rm
- `--no-preserve-root` detection requires `rm` context (prevents false positive on echo)
- Tests: 79 → 82

## [1.6.0] - 2026-03-22
- **Security fix: `rm -rf .` now blocked** — current directory deletion was previously allowed
- Also blocks `rm -rf ./` (trailing slash variant)
- `rm -rf ./subdirectory` still allowed (safe subdirectory deletion)
- Tests: 76 → 79
## [1.5.4] - 2026-03-22
- Secret-guard edge case tests: .env.production, id_rsa, .env.local
- Branch-guard edge case tests: force-with-lease, HEAD:main push
- Tests: 72 → 76
- Headless mode limitation note in README (#36071)

## [1.5.3] - 2026-03-22
- Branch-guard edge case tests: force-with-lease, HEAD:main push
- Tests: 69 → 72

## [1.5.2] - 2026-03-22
- **Expanded `--verify` tests**: 8 → 12 (compound commands, force-push, git reset --hard, sudo)
- **New example: auto-approve-build.sh** — auto-approve npm/cargo/go/python build/test/lint commands
- **New example: edit-guard.sh** — defense-in-depth for Edit/Write deny bypass (#37210)
- **FAQ section** in README (skills vs hooks confusion, health-check interpretation, performance)
- Hook count fix in README: 7 → 8
- COOKBOOK recipe count: 8 → 9
- Tests: 66 → 69 (api-error-alert coverage)

## [1.5.1] - 2026-03-21
- npm packaging fix

## [1.5.0] - 2026-03-21
- **New hook: API Error Alert** — notifies when sessions die from rate limits, auth failures, or server errors
- Desktop notification (macOS/Linux/WSL2) + error log
- 7 → 8 hooks total
- --verify now tests all 8 hooks (8/8)

## [1.4.1] - 2026-03-21
- **Fix: compound command detection** — `cd /tmp && git checkout --force` now correctly blocked
- Tests: 61 → 63

## [1.4.0] - 2026-03-21
- **New: git checkout/switch --force protection** — blocks `--force`, `-f`, `--discard-changes`
- **Fix: sudo check was unreachable** — early `exit 0` before Check 6 made sudo protection dead code
- Tests: 56 → 61

## [1.3.0] - 2026-03-21
- **New: `--verify` option** — sends test inputs to each installed hook, confirms block/allow behavior (6 tests)
- `--status` now returns exit code 1 when hooks are missing (CI-friendly)
- Tests: 44 → 56 (+12 edge cases for destructive-guard and secret-guard)
- New edge case tests: `rm -rf /var`, `git add .` with .env, `git add -A`, `.env.production`, `.pem`

## [1.2.1] - 2026-03-21
- README: updated COOKBOOK recipe count (6 → 8)
- npm publish with latest README

## [1.2.0] - 2026-03-21
- **New: `--status` option** — check which hooks are installed and settings.json configuration
- Tests: 41 → 44

## [1.1.3] - 2026-03-21
- Added `.npmignore` to reduce package size (82KB → 42KB)
- Tests: 39 → 41 (added CLI smoke tests for --help and --dry-run)
- All 7 hooks now have test coverage

## [1.1.2] - 2026-03-21
- Improved npm search discoverability (16 keywords)
- Added `npm test` script

## [1.1.1] - 2026-03-21
- Added `sudo` protection to destructive-guard (blocks `sudo rm -rf`, `sudo chmod 777`)
- Tests: 33 → 35

## [1.1.0] - 2026-03-21
- **New hook: secret-guard** — blocks `git add .env`, credential files, `git add .` with .env present
- **Enhanced branch-guard** — now blocks `--force` push on ALL branches (configurable via `CC_ALLOW_FORCE_PUSH=1`)
- 6 → 7 hooks total
- Added 33 automated tests (`bash test.sh`)
- Added GitHub Actions CI
- Added animated terminal demo SVG to README
- README now references related GitHub Issues (#6527, #16561, #36339, #36640)

## [1.0.10] - 2026-03-20
- Fixed false positives in destructive-guard (git reset --hard in echo/string arguments)
- Moved hook scripts to external `scripts.json` (fixes template literal crash)
- Added NFS mount detection to destructive-guard (#36640)
- Added block logging to `~/.claude/blocked-commands.log`

## [1.0.0] - 2026-03-20
- Initial release with 6 hooks:
  - destructive-guard (rm -rf, git reset --hard, git clean)
  - branch-guard (main/master push protection)
  - syntax-check (Python, Shell, JSON, YAML, JS)
  - context-monitor (graduated warnings at 40/25/20/15%)
  - comment-strip (bash comments breaking permissions, #29582)
  - cd-git-allow (auto-approve read-only cd+git compounds, #32985)

- **New: git checkout/switch --force protection** — blocks `git checkout --force`, `git switch --force`, `git switch --discard-changes`
- **Fix: sudo check was unreachable** — early `exit 0` before Check 6 made sudo protection dead code
- Tests: 56 → 61 (+5 git checkout/switch tests)
- Inspired by competitor safety-net v0.8.0 git rules
