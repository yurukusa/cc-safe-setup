# Changelog

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
