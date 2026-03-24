# cc-safe-setup

[![npm version](https://img.shields.io/npm/v/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![npm downloads](https://img.shields.io/npm/dw/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![tests](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml/badge.svg)](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml)

**One command to make Claude Code safe for autonomous operation.** [日本語](docs/README.ja.md)

8 built-in + 77 examples = **85 hooks**. 28 CLI commands. 423 tests. [Web Tool](https://yurukusa.github.io/cc-safe-setup/) · [Cheat Sheet](https://yurukusa.github.io/cc-safe-setup/hooks-cheatsheet.html) · [Builder](https://yurukusa.github.io/cc-safe-setup/builder.html) · [FAQ](https://yurukusa.github.io/cc-safe-setup/faq.html) · [Playground](https://yurukusa.github.io/cc-hook-registry/playground.html)

```bash
npx cc-safe-setup
```

Installs 8 production-tested safety hooks in ~10 seconds. Zero dependencies. No manual configuration.

```
  cc-safe-setup
  Make Claude Code safe for autonomous operation

  Prevents real incidents (from GitHub Issues):
  ✗ rm -rf deleted entire user directory via NTFS junction (#36339)
  ✗ Remove-Item -Recurse -Force destroyed unpushed source (#37331)
  ✗ Entire Mac filesystem deleted during cleanup (#36233)
  ✗ Untested code pushed to main at 3am
  ✗ Force-push rewrote shared branch history
  ✗ API keys committed to public repos via git add .
  ✗ Syntax errors cascading through 30+ files
  ✗ Sessions losing all context with no warning

  Hooks to install:

  ● Destructive Command Blocker
  ● Branch Push Protector
  ● Post-Edit Syntax Validator
  ● Context Window Monitor
  ● Bash Comment Stripper
  ● cd+git Auto-Approver
  ● Secret Leak Prevention

  Install all 8 safety hooks? [Y/n] Y

  ✓ Done. 8 safety hooks installed.
```

## Why This Exists

A Claude Code user [lost their entire C:\Users directory](https://github.com/anthropics/claude-code/issues/36339) when `rm -rf` followed NTFS junctions. Another [lost all source code](https://github.com/anthropics/claude-code/issues/37331) when Claude ran `Remove-Item -Recurse -Force *` on a repo. Others had untested code pushed to main at 3am. API keys got committed via `git add .`. Syntax errors cascaded through 30+ files before anyone noticed.

Claude Code ships with no safety hooks by default. This tool fixes that.

## What Gets Installed

| Hook | Prevents | Related Issues |
|------|----------|----------------|
| **Destructive Guard** | `rm -rf /`, `git reset --hard`, `git clean -fd`, `git checkout --force`, `sudo` + destructive, PowerShell `Remove-Item -Recurse -Force`, `rd /s /q`, NFS mount detection | [#36339](https://github.com/anthropics/claude-code/issues/36339) [#36640](https://github.com/anthropics/claude-code/issues/36640) [#37331](https://github.com/anthropics/claude-code/issues/37331) |
| **Branch Guard** | Pushes to main/master + force-push (`--force`) on all branches | |
| **Secret Guard** | `git add .env`, credential files, `git add .` with .env present | [#6527](https://github.com/anthropics/claude-code/issues/6527) |
| **Syntax Check** | Python, Shell, JSON, YAML, JS errors after edits | |
| **Context Monitor** | Session state loss from context window overflow (40%→25%→20%→15% warnings) | |
| **Comment Stripper** | Bash comments breaking permission allowlists | [#29582](https://github.com/anthropics/claude-code/issues/29582) |
| **cd+git Auto-Approver** | Permission prompt spam for `cd /path && git log` | [#32985](https://github.com/anthropics/claude-code/issues/32985) [#16561](https://github.com/anthropics/claude-code/issues/16561) |
| **API Error Alert** | Silent session death from rate limits or API errors — desktop notification + log | |

Each hook exists because a real incident happened without it.

## All 26 Commands

| Command | What It Does |
|---------|-------------|
| `npx cc-safe-setup` | Install 8 safety hooks |
| `--create "desc"` | Generate hook from plain English |
| `--audit [--fix\|--json\|--badge]` | Safety score 0-100 |
| `--lint` | Static analysis of config |
| `--diff <file>` | Compare settings |
| `--compare <a> <b>` | Side-by-side hook comparison |
| `--migrate` | Detect hooks from other projects |
| `--generate-ci` | Create GitHub Actions workflow |
| `--share` | Generate shareable URL |
| `--benchmark` | Measure hook speed |
| `--dashboard` | Real-time terminal UI |
| `--issues` | GitHub Issues each hook addresses |
| `--doctor` | Diagnose hook problems |
| `--watch` | Live blocked command feed |
| `--stats` | Block history analytics |
| `--learn [--apply]` | Pattern learning |
| `--scan [--apply]` | Tech stack detection |
| `--export / --import` | Team config sharing |
| `--verify` | Test each hook |
| `--install-example <name>` | Install from 75 examples |
| `--examples [filter]` | Browse examples by keyword |
| `--full` | All-in-one setup |
| `--status` | Check installed hooks |
| `--dry-run` | Preview changes |
| `--uninstall` | Remove all hooks |
| `--help` | Show help |

## How It Works

1. Writes hook scripts to `~/.claude/hooks/`
2. Updates `~/.claude/settings.json` to register the hooks
3. Restart Claude Code — hooks are active

Safe to run multiple times. Existing settings are preserved. A backup is created if settings.json can't be parsed.

**Preview first:** `npx cc-safe-setup --dry-run`

**Check status:** `npx cc-safe-setup --status` — see which hooks are installed (exit code 1 if missing).

**Verify hooks work:** `npx cc-safe-setup --verify` — sends test inputs to each hook and confirms they block/allow correctly.

**Troubleshoot:** `npx cc-safe-setup --doctor` — diagnoses why hooks aren't working (jq, permissions, paths, shebang).

**Live monitor:** `npx cc-safe-setup --watch` — real-time dashboard of blocked commands during autonomous sessions.

**Uninstall:** `npx cc-safe-setup --uninstall` — removes all hooks and cleans settings.json.

**Requires:** [jq](https://jqlang.github.io/jq/) for JSON parsing (`brew install jq` / `apt install jq`).

**Note:** Hooks are skipped when Claude Code runs with `--bare` or `--dangerously-skip-permissions`. These modes bypass all safety hooks by design.

**Known limitation:** In headless mode (`-p` / `--print`), hook exit code 2 may not block tool execution ([#36071](https://github.com/anthropics/claude-code/issues/36071)). For CI pipelines, use interactive mode with hooks rather than `-p` mode.

## Before / After

Run `npx cc-health-check` to see the difference:

| | Before | After |
|---|--------|-------|
| Safety Guards | 25% | **75%** |
| Overall Score | 50/100 | **95/100** |
| Destructive commands | Unprotected | Blocked |
| Force push | Allowed | Blocked |
| `.env` in git | Possible | Blocked |
| Context warnings | None | 4-stage alerts |

## Configuration

| Variable | Hook | Default |
|----------|------|---------|
| `CC_ALLOW_DESTRUCTIVE=1` | destructive-guard | `0` (protection on) |
| `CC_SAFE_DELETE_DIRS` | destructive-guard | `node_modules:dist:build:.cache:__pycache__:coverage` |
| `CC_PROTECT_BRANCHES` | branch-guard | `main:master` |
| `CC_ALLOW_FORCE_PUSH=1` | branch-guard | `0` (protection on) |
| `CC_SECRET_PATTERNS` | secret-guard | `.env:.env.local:credentials:*.pem:*.key` |
| `CC_CONTEXT_MISSION_FILE` | context-monitor | `$HOME/mission.md` |

## After Installing

Verify your setup:

```bash
npx cc-health-check
```

## Full Kit

cc-safe-setup gives you 8 essential hooks. For the complete autonomous operation toolkit:

**[Claude Code Ops Kit](https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=github&utm_medium=readme&utm_campaign=safe-setup)** — 16 hooks + 5 templates + 3 exclusive tools + install.sh. Production-ready in 15 minutes.

Or start with the free hooks: [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks)

## Examples

## Safety Audit

**[Try it in your browser](https://yurukusa.github.io/cc-safe-setup/)** — paste your settings.json, get a score instantly. Nothing leaves your browser.

Or from the CLI:

```bash
npx cc-safe-setup --audit
```

Analyzes 9 safety dimensions and gives you a score (0-100) with one-command fixes for each risk.

### CI Integration (GitHub Action)

```yaml
# .github/workflows/safety.yml
- uses: yurukusa/cc-safe-setup@main
  with:
    threshold: 70  # CI fails if score drops below this
```

### Project Scanner

```bash
npx cc-safe-setup --scan         # detect tech stack, recommend hooks
npx cc-safe-setup --scan --apply # auto-create CLAUDE.md with project rules
```

### Create Hooks from Plain English

```bash
npx cc-safe-setup --create "block npm publish without tests"
npx cc-safe-setup --create "auto approve test commands"
npx cc-safe-setup --create "block curl pipe to bash"
npx cc-safe-setup --create "block DROP TABLE and TRUNCATE"
```

9 built-in templates + generic fallback. Creates the script, registers it, and runs a smoke test.

### Self-Learning Safety

```bash
npx cc-safe-setup --learn        # analyze your block history for patterns
npx cc-safe-setup --learn --apply # auto-generate custom hooks from patterns
```

## Examples

Need custom hooks beyond the 8 built-in ones? Install any example with one command:

```bash
npx cc-safe-setup --install-example block-database-wipe
```

Or browse all available examples in [`examples/`](examples/):

- **auto-approve-git-read.sh** — Auto-approve `git status`, `git log`, even with `-C` flags
- **auto-approve-ssh.sh** — Auto-approve safe SSH commands (`uptime`, `whoami`, etc.)
- **enforce-tests.sh** — Warn when source files change without corresponding test files
- **notify-waiting.sh** — Desktop notification when Claude Code waits for input (macOS/Linux/WSL2)
- **edit-guard.sh** — Block Edit/Write to protected files (defense-in-depth for [#37210](https://github.com/anthropics/claude-code/issues/37210))
- **auto-approve-build.sh** — Auto-approve npm/yarn/cargo/go/python build, test, and lint commands
- **auto-approve-docker.sh** — Auto-approve docker build, compose, ps, logs, and other safe commands
- **block-database-wipe.sh** — Block destructive database commands: Laravel `migrate:fresh`, Django `flush`, Rails `db:drop`, raw `DROP DATABASE` ([#37405](https://github.com/anthropics/claude-code/issues/37405) [#37439](https://github.com/anthropics/claude-code/issues/37439))
- **auto-approve-python.sh** — Auto-approve pytest, mypy, ruff, black, isort, flake8, pylint commands
- **auto-snapshot.sh** — Auto-save file snapshots before edits for rollback protection ([#37386](https://github.com/anthropics/claude-code/issues/37386) [#37457](https://github.com/anthropics/claude-code/issues/37457))
- **allowlist.sh** — Block everything not explicitly approved — inverse permission model ([#37471](https://github.com/anthropics/claude-code/issues/37471))
- **protect-dotfiles.sh** — Block modifications to `~/.bashrc`, `~/.aws/`, `~/.ssh/` and chezmoi without diff ([#37478](https://github.com/anthropics/claude-code/issues/37478))
- **scope-guard.sh** — Block file operations outside project directory — absolute paths, home, parent escapes ([#36233](https://github.com/anthropics/claude-code/issues/36233))
- **auto-checkpoint.sh** — Auto-commit after every edit for rollback protection ([#34674](https://github.com/anthropics/claude-code/issues/34674))
- **git-config-guard.sh** — Block `git config --global` modifications without consent ([#37201](https://github.com/anthropics/claude-code/issues/37201))
- **deploy-guard.sh** — Block deploy commands when uncommitted changes exist ([#37314](https://github.com/anthropics/claude-code/issues/37314))
- **network-guard.sh** — Warn on suspicious network commands sending file contents ([#37420](https://github.com/anthropics/claude-code/issues/37420))
- **test-before-push.sh** — Block `git push` when tests haven't been run ([#36970](https://github.com/anthropics/claude-code/issues/36970))
- **large-file-guard.sh** — Warn when Write tool creates files over 500KB
- **commit-message-check.sh** — Warn on non-conventional commit messages (feat:, fix:, docs:, etc.)
- **env-var-check.sh** — Block hardcoded API keys (sk-, ghp_, glpat-) in export commands
- **timeout-guard.sh** — Warn before long-running commands (npm start, rails s, docker-compose up)
- **branch-name-check.sh** — Warn on non-conventional branch names (feature/, fix/, etc.)
- **todo-check.sh** — Warn when committing files with TODO/FIXME/HACK markers
- **path-traversal-guard.sh** — Block Edit/Write with `../../` path traversal and system directories
- **case-sensitive-guard.sh** — Detect case-insensitive filesystems (exFAT, NTFS, HFS+) and block rm/mkdir that would collide due to case folding ([#37875](https://github.com/anthropics/claude-code/issues/37875))
- **compound-command-approver.sh** — Auto-approve safe compound commands (`cd && git log`, `cd && npm test`) that the permission system can't match ([#30519](https://github.com/anthropics/claude-code/issues/30519) [#16561](https://github.com/anthropics/claude-code/issues/16561))
- **tmp-cleanup.sh** — Clean up accumulated `/tmp/claude-*-cwd` files on session end ([#8856](https://github.com/anthropics/claude-code/issues/8856))
- **session-checkpoint.sh** — Save session state to mission file before context compaction ([#37866](https://github.com/anthropics/claude-code/issues/37866))
- **verify-before-commit.sh** — Block git commit when lint/test commands haven't been run ([#37818](https://github.com/anthropics/claude-code/issues/37818))
- **hook-debug-wrapper.sh** — Wrap any hook to log input/output/exit code/timing to `~/.claude/hook-debug.log`
- **loop-detector.sh** — Detect and break command repetition loops (warn at 3, block at 5 repeats)
- **commit-quality-gate.sh** — Warn on vague commit messages ("update code"), long subjects, mega-commits
- **session-handoff.sh** — Auto-save git state and session info to `~/.claude/session-handoff.md` on session end
- **diff-size-guard.sh** — Warn/block when committing too many files at once (default: warn at 10, block at 50)
- **dependency-audit.sh** — Warn when installing packages not in manifest (npm/pip/cargo supply chain awareness)
- **env-source-guard.sh** — Block sourcing .env files into shell environment ([#401](https://github.com/anthropics/claude-code/issues/401))
- **symlink-guard.sh** — Detect symlink/junction traversal in rm targets ([#36339](https://github.com/anthropics/claude-code/issues/36339) [#764](https://github.com/anthropics/claude-code/issues/764))
- **no-sudo-guard.sh** — Block all sudo commands
- **no-install-global.sh** — Block npm -g and system-wide pip
- **no-curl-upload.sh** — Warn on curl POST/upload (data exfiltration)
- **no-port-bind.sh** — Warn on network port binding
- **git-tag-guard.sh** — Block pushing all tags at once
- **npm-publish-guard.sh** — Version check before npm publish
- **max-file-count-guard.sh** — Warn when 20+ new files created per session
- **protect-claudemd.sh** — Block edits to CLAUDE.md and settings files
- **reinject-claudemd.sh** — Re-inject CLAUDE.md rules after compaction ([#6354](https://github.com/anthropics/claude-code/issues/6354))
- **binary-file-guard.sh** — Warn when Write targets binary file types (images, archives)
- **stale-branch-guard.sh** — Warn when working branch is far behind default
- **cost-tracker.sh** — Estimate session token cost and warn at thresholds ($1, $5)
- **read-before-edit.sh** — Warn when editing files not recently read (prevents old_string mismatches)

## Safety Checklist

**[SAFETY_CHECKLIST.md](SAFETY_CHECKLIST.md)** — Copy-paste checklist for before/during/after autonomous sessions.

## Troubleshooting

**[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — "Hook doesn't work" → step-by-step diagnosis. Covers every common failure pattern.

## settings.json Reference

**[SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)** — Complete reference for permissions, hooks, modes, and common configurations. Includes known limitations and workarounds.

## Migration Guide

**[MIGRATION.md](MIGRATION.md)** — Step-by-step guide for moving from permissions-only to permissions + hooks. Keep your existing config, add safety layers on top.

## Learn More

- [Official Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks) — Claude Code hooks documentation
- [Hooks Cookbook](https://github.com/yurukusa/claude-code-hooks/blob/main/COOKBOOK.md) — 25 recipes from real GitHub Issues ([interactive version](https://yurukusa.github.io/claude-code-hooks/))
- [Japanese guide (Qiita)](https://qiita.com/yurukusa/items/a9714b33f5d974e8f1e8) — この記事の日本語解説
- [Hook Test Runner](https://github.com/yurukusa/cc-hook-test) — `npx cc-hook-test <hook.sh>` to auto-test any hook
- [Hook Registry](https://github.com/yurukusa/cc-hook-registry) — `npx cc-hook-registry search database` ([browse online](https://yurukusa.github.io/cc-hook-registry/))
- [Hooks Cheat Sheet](https://yurukusa.github.io/cc-safe-setup/cheatsheet.html) — printable A4 quick reference
- [Ecosystem Comparison](https://yurukusa.github.io/cc-safe-setup/ecosystem.html) — all Claude Code hook projects compared
- [The incident that inspired this tool](https://github.com/anthropics/claude-code/issues/36339) — NTFS junction rm -rf

## FAQ

**Q: I installed hooks but Claude says "Unknown skill: claude-code-hooks:setup"**

cc-safe-setup installs **hooks**, not skills or plugins. Hooks run automatically in the background — you don't invoke them manually. After install + restart, try running a dangerous command; the hook will block it silently.

**Q: `cc-health-check` says to run `cc-safe-setup` but I already did**

cc-safe-setup covers Safety Guards (75-100%) and Monitoring (context-monitor). The other health check dimensions (Code Quality, Recovery, Coordination) require additional CLAUDE.md configuration or manual hook installation from [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks).

**Q: Will hooks slow down Claude Code?**

No. Each hook runs in ~10ms. They only fire on specific events (before tool use, after edits, on stop). No polling, no background processes.

## Contributing

Found a false positive? Open an [issue](https://github.com/yurukusa/cc-safe-setup/issues/new?template=false_positive.md). Want a new hook? Open a [feature request](https://github.com/yurukusa/cc-safe-setup/issues/new?template=bug_report.md).

If cc-safe-setup saved your project from a destructive command, consider giving it a star — it helps others find this tool.

## License

MIT
