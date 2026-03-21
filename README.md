# cc-safe-setup

[![npm version](https://img.shields.io/npm/v/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![npm downloads](https://img.shields.io/npm/dw/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![tests](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml/badge.svg)](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml)

**One command to make Claude Code safe for autonomous operation.**

Not just a destructive command blocker — 7 hooks covering safety, quality, monitoring, and developer experience.

```bash
npx cc-safe-setup
```

Installs 7 production-tested safety hooks in ~10 seconds. Zero dependencies. No manual configuration.

```
  cc-safe-setup
  Make Claude Code safe for autonomous operation

  Prevents real incidents:
  ✗ rm -rf deleting entire user directories (NTFS junction traversal)
  ✗ Untested code pushed to main at 3am
  ✗ Force-push rewriting shared branch history
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

  Install all 7 safety hooks? [Y/n] Y

  ✓ Done. 7 safety hooks installed.
```

## Why This Exists

A Claude Code user [lost their entire C:\Users directory](https://github.com/anthropics/claude-code/issues/36339) when `rm -rf` followed NTFS junctions. Another had untested code pushed to main at 3am. API keys got committed via `git add .`. Syntax errors cascaded through 30+ files before anyone noticed.

Claude Code ships with no safety hooks by default. This tool fixes that.

## What Gets Installed

| Hook | Prevents | Related Issues |
|------|----------|----------------|
| **Destructive Guard** | `rm -rf /`, `git reset --hard`, `git clean -fd`, NFS mount detection | [#36339](https://github.com/anthropics/claude-code/issues/36339) [#36640](https://github.com/anthropics/claude-code/issues/36640) |
| **Branch Guard** | Pushes to main/master + force-push (`--force`) on all branches | |
| **Secret Guard** | `git add .env`, credential files, `git add .` with .env present | [#6527](https://github.com/anthropics/claude-code/issues/6527) |
| **Syntax Check** | Python, Shell, JSON, YAML, JS errors after edits | |
| **Context Monitor** | Session state loss from context window overflow (40%→25%→20%→15% warnings) | |
| **Comment Stripper** | Bash comments breaking permission allowlists | [#29582](https://github.com/anthropics/claude-code/issues/29582) |
| **cd+git Auto-Approver** | Permission prompt spam for `cd /path && git log` | [#32985](https://github.com/anthropics/claude-code/issues/32985) [#16561](https://github.com/anthropics/claude-code/issues/16561) |

Each hook exists because a real incident happened without it.

## How It Works

1. Writes hook scripts to `~/.claude/hooks/`
2. Updates `~/.claude/settings.json` to register the hooks
3. Restart Claude Code — hooks are active

Safe to run multiple times. Existing settings are preserved. A backup is created if settings.json can't be parsed.

**Preview first:** `npx cc-safe-setup --dry-run`

**Check status:** `npx cc-safe-setup --status` — see which hooks are installed (exit code 1 if missing).

**Verify hooks work:** `npx cc-safe-setup --verify` — sends test inputs to each hook and confirms they block/allow correctly.

**Uninstall:** `npx cc-safe-setup --uninstall` — removes all hooks and cleans settings.json.

**Requires:** [jq](https://jqlang.github.io/jq/) for JSON parsing (`brew install jq` / `apt install jq`).

**Note:** Hooks are skipped when Claude Code runs with `--bare` or `--dangerously-skip-permissions`. These modes bypass all safety hooks by design.

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

cc-safe-setup gives you 7 essential hooks. For the complete autonomous operation toolkit:

**[Claude Code Ops Kit](https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=github&utm_medium=readme&utm_campaign=safe-setup)** — 16 hooks + 5 templates + 3 exclusive tools + install.sh. Production-ready in 15 minutes.

Or start with the free hooks: [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks)

## Learn More

- [Official Hooks Reference](https://code.claude.com/docs/en/hooks) — Claude Code hooks documentation
- [Hooks Cookbook](https://github.com/yurukusa/claude-code-hooks/blob/main/COOKBOOK.md) — 8 ready-to-use recipes from real GitHub Issues
- [Japanese guide (Qiita)](https://qiita.com/yurukusa/items/a9714b33f5d974e8f1e8) — この記事の日本語解説
- [The incident that inspired this tool](https://github.com/anthropics/claude-code/issues/36339) — NTFS junction rm -rf

## Contributing

Found a false positive? Open an [issue](https://github.com/yurukusa/cc-safe-setup/issues/new?template=false_positive.md). Want a new hook? Open a [feature request](https://github.com/yurukusa/cc-safe-setup/issues/new?template=bug_report.md).

If cc-safe-setup saved your project from a destructive command, consider giving it a star — it helps others find this tool.

## License

MIT
