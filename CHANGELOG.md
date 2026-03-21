# Changelog

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

## [1.2.0] - 2026-03-21
- **New: `--status` option** — check which hooks are installed and settings.json configuration
- Tests: 41 → 42
