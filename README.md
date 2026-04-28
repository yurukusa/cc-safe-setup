# cc-safe-setup

[![npm version](https://img.shields.io/npm/v/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![npm downloads](https://img.shields.io/npm/dw/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![tests](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml/badge.svg)](https://github.com/yurukusa/cc-safe-setup/actions/workflows/test.yml)

> 🚀 **Launching on [Product Hunt](https://www.producthunt.com/products/cc-safe-setup) — April 21!** Follow us and upvote to support open source safety for AI coding agents.

**One command to make Claude Code safe for autonomous operation.** 715 example hooks · 9,200+ tests · 30K+ total installs · [日本語](docs/README.ja.md)

```bash
npx cc-safe-setup
```

Installs 8 safety hooks in ~10 seconds. Blocks `rm -rf /`, prevents pushes to main, catches secret leaks, validates syntax after every edit. Zero npm dependencies. Hooks use [`jq`](https://jqlang.github.io/jq/) at runtime (`brew install jq` / `apt install jq`).

> **What's a hook?** A checkpoint that runs before Claude executes a command. Like airport security — it inspects what's about to happen and blocks anything dangerous before it reaches the gate.

[**▶ Live Demo**](https://yurukusa.github.io/cc-safe-setup/demo.html) (see hooks block rm -rf in your browser) · [**Incident Tracker**](https://yurukusa.github.io/cc-safe-setup/incidents.html) (90 real incidents) · [**Token Checkup**](https://yurukusa.github.io/cc-safe-setup/token-checkup.html) (what type are you?) · [**All 8 Tools**](https://yurukusa.github.io/cc-safe-setup/hub.html)

```
  cc-safe-setup
  Make Claude Code safe for autonomous operation

  Prevents real incidents (from GitHub Issues):
  ✗ rm -rf permanently destroyed ~50 GB / 1,500 files (#49129) ← April 2026
  ✗ Auto mode approved ~/.ssh deletion — all SSH keys gone (#49554)
  ✗ ~/.git-credentials PATs deleted without confirmation (#49539)
  ✗ rm -rf deleted 3,467 files (~7 GB) without confirmation (#46058)
  ✗ rm -rf deleted entire user directory via NTFS junction (#36339)
  ✗ Remove-Item -Recurse -Force destroyed unpushed source (#37331)
  ✗ Entire Mac filesystem deleted during cleanup (#36233)
  ✗ Untested code pushed to main at 3am
  ✗ Force-push rewrote shared branch history
  ✗ API keys committed to public repos via git add .
  ✗ Syntax errors cascading through 30+ files
  ✗ Sessions losing all context with no warning
  ✗ CLAUDE.md rules silently ignored after context compaction
  ✗ Claude ran destructive DDL on production database (#46684)
  ✗ AI executed delete/kill operations on production environment (#46650)
  ✗ Subagents ignoring all CLAUDE.md rules since v2.1.84 (#40459)

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

A user [lost 3,467 files (~7 GB)](https://github.com/anthropics/claude-code/issues/46058) when Claude ran `rm -rf` on their data directory without confirmation. Another [lost their entire C:\Users directory](https://github.com/anthropics/claude-code/issues/36339) when `rm -rf` followed NTFS junctions. Another [lost all source code](https://github.com/anthropics/claude-code/issues/37331) when Claude ran `Remove-Item -Recurse -Force *` on a repo. One user's Claude [ran destructive DDL on a production database](https://github.com/anthropics/claude-code/issues/46684) when asked only to investigate. Another had Claude [execute delete and kill operations on production systems](https://github.com/anthropics/claude-code/issues/46650). Others had untested code pushed to main at 3am. API keys got committed via `git add .`. Syntax errors cascaded through 30+ files before anyone noticed. And [CLAUDE.md rules get silently dropped](https://github.com/anthropics/claude-code/issues/6354) after context compaction — your instructions vanish mid-session.

One user [analyzed 6,852 sessions](https://github.com/anthropics/claude-code/issues/42796) and found the Read:Edit ratio dropped from 6.6 to 2.0 — Claude editing files it never read jumped from 6% to 34%. That issue has over 2,100 reactions. The `read-before-edit` example hook catches this pattern before damage happens.

In April 2026, [$1,446 was transferred without authorization](https://github.com/anthropics/claude-code/issues/46828) when Claude moved funds between exchange accounts. A user [lost $367 and got their account suspended](https://github.com/anthropics/claude-code/issues/47046) from a Claude-generated script. [Physical coordinates were uploaded to a public website](https://github.com/anthropics/claude-code/issues/46910) despite 17 sessions of "no PII" in CLAUDE.md. And [deny rules can be bypassed with 50+ subcommands](https://adversa.ai/blog/claude-code-security-bypass-deny-rules-disabled/).

Claude Code ships with no safety hooks by default. This tool fixes that. ([Standalone guard script](https://gist.github.com/yurukusa/87f51b97bb655357dd148b66109d0c14) for quick setup | [Database protection hooks](https://gist.github.com/yurukusa/ad27e541769992e9e0cd15c1b487a1d2) | [Credential protection hooks](https://gist.github.com/yurukusa/7292ead735df0aa673f0485eba5587f3) | [Fabrication detection hook](https://gist.github.com/yurukusa/03f4bbbab61f7ddf31049cc28a01d0d9) | [Security vulnerability hooks](https://gist.github.com/yurukusa/81f79ae6d760b27c17f2cd642ea846d7))

**Works with Auto Mode.** Claude Code's [Auto Mode sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing) provides container-level isolation. cc-safe-setup adds process-level hooks as defense-in-depth — catching destructive commands even outside sandboxed environments.

**Works with subagents.** Since v2.1.84, subagents and teammates [don't receive CLAUDE.md](https://github.com/anthropics/claude-code/issues/40459) — your project rules are silently skipped. Hooks operate at the process level, but [subagent tool calls may bypass PreToolUse hooks](https://github.com/anthropics/claude-code/issues/21460) in some configurations. As defense-in-depth, cc-safe-setup installs hooks at the user level (`~/.claude/settings.json`). The `subagent-claudemd-inject` example hook re-injects critical rules into subagent prompts.

### 🚨 Opus 4.7 Crisis (April 2026)

Opus 4.7 broke auto mode's safety classifier — it was [hardcoded to Opus 4.6](https://github.com/anthropics/claude-code/issues/49618). **If you use auto mode with Opus 4.7, dangerous commands run without the built-in safety check.** In 3 days: [50 GB permanently deleted](https://github.com/anthropics/claude-code/issues/49129), [~/.ssh wiped](https://github.com/anthropics/claude-code/issues/49554), [git credentials destroyed](https://github.com/anthropics/claude-code/issues/49539), [shell configs truncated to 0 bytes](https://github.com/anthropics/claude-code/issues/49615). Users report [4x token consumption](https://github.com/anthropics/claude-code/issues/49541) from silent model switches.

**One command to fix it:**

```bash
npx cc-safe-setup --opus47
```

Installs 4 hooks targeting known Opus 4.7 regressions. [Full details →](https://yurukusa.github.io/cc-safe-setup/opus-47-survival-guide.html) · [Emergency Defense Kit (Gist)](https://gist.github.com/yurukusa/6747ea655cc5c374a1ec9ed4fba027e4) · [Safety Scanner](https://yurukusa.github.io/cc-safe-setup/opus47-scanner.html)

## What Gets Installed

| Hook | Prevents | Related Issues |
|------|----------|----------------|
| **Destructive Guard** | `rm -rf /`, `git reset --hard`, `git clean -fd`, `git checkout --force`, `sudo` + destructive, PowerShell `Remove-Item -Recurse -Force`, `rd /s /q`, NFS mount detection | [#46058](https://github.com/anthropics/claude-code/issues/46058) [#36339](https://github.com/anthropics/claude-code/issues/36339) [#36640](https://github.com/anthropics/claude-code/issues/36640) [#37331](https://github.com/anthropics/claude-code/issues/37331) |
| **Branch Guard** | Pushes to main/master + force-push (`--force`) on all branches | |
| **Secret Guard** | `git add .env`, credential files, `git add .` with .env present | [#6527](https://github.com/anthropics/claude-code/issues/6527) |
| **Syntax Check** | Python, Shell, JSON, YAML, JS errors after edits | |
| **Context Monitor** | Session state loss from context window overflow (40%→25%→20%→15% warnings) | |
| **Comment Stripper** | Bash comments breaking permission allowlists | [#29582](https://github.com/anthropics/claude-code/issues/29582) |
| **cd+git Auto-Approver** | Permission prompt spam for `cd /path && git log` | [#32985](https://github.com/anthropics/claude-code/issues/32985) [#16561](https://github.com/anthropics/claude-code/issues/16561) |
| **API Error Alert** | Silent session death from rate limits or API errors — desktop notification + log | |

Each hook exists because a real incident happened without it.

### Free diagnostic tools

| Tool | What it does |
|------|-------------|
| **[Token Checkup](https://yurukusa.github.io/cc-safe-setup/token-checkup.html)** | 5 questions → find where your tokens are going (30 seconds) |
| **[Security Checkup](https://yurukusa.github.io/cc-safe-setup/security-checkup.html)** | 6 questions based on real incidents ($1,800+ in losses) |
| **[Version Check](https://yurukusa.github.io/cc-safe-setup/version-check.html)** | Is your CC version affected by cache inflation? |

### Free guides

| Guide | What it covers |
|-------|----------------|
| **[6-hook fortification for the 2026-04 regression cluster](https://gist.github.com/yurukusa/79eeabd11dbfa29d99e7f2a058391286)** | The April 2026 postmortem recap + which 6 cc-safe-setup hooks would have caught each issue. No signup. |
| **[Find which CC versions ran your cache regression sessions](https://gist.github.com/yurukusa/60b21cc133769e0bedab0b828bca4f90)** | One-line `grep + jq` diagnostic over `~/.claude/` logs. Shows per-day per-version count of sessions affected by [#46829](https://github.com/anthropics/claude-code/issues/46829)/[#46917](https://github.com/anthropics/claude-code/issues/46917). |
| **[`/usage --json`: 5 fields, one ratio that decides whether you migrate](https://yurukusa.hashnode.dev/how-to-read-usage-json-5-fields-one-ratio-that-decides-whether-you-migrate)** | `cache_creation_ratio` cheat sheet for the v2.1.118 `/usage --json` output. Five fields and one ratio with HEALTHY / WATCH / TRIGGER bands so you can decide migration timing from your own logs, no third-party dashboard. |
| **[PocketOS 9-second wipe — 3-prevention audit script](https://gist.github.com/yurukusa/f4e9104ff5bb331b21c9446bffb57d91)** | Read-only audit script (Railway / AWS / GCP / GitHub examples) for the three preventions surfaced by the [2026-04-25 PocketOS production-database wipe](https://yurukusa.hashnode.dev/9-seconds-no-backups-what-the-pocketos-wipe-tells-you-to-harden-before-friday) ([HN 817pt](https://news.ycombinator.com/item?id=47911524)). No destructive commands; prints questions and read-only checks you run yourself. |
| **[Postmortems incident #1 free preview — cache TTL regression Signal + Diagnosis](https://gist.github.com/yurukusa/9f597e27d4a44de85d4c8815a84b4f5d)** | Verbatim chapter excerpt from the upcoming Postmortems book (ships 2026-05-05). Three read-only checks (one minute total) to tell whether the [March 2026 cache TTL regression](https://github.com/anthropics/claude-code/issues/46829) hit your sessions, no purchase required. |

### Go deeper

| Resource | What you get | Price |
|----------|-------------|-------|
| **[Token Book](https://yurukusa.github.io/cc-safe-setup/token-book.html)** | Cut token consumption in half. CLAUDE.md templates, hook configs, context management, 32 failure patterns with fixes. 44,000+ words from 800+ hours of real operation data. | ¥2,500 (~$17). Ch.1 free |
| **[Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook)** | Stay, switch, or hybridize? Six-week timeline of the April 2026 quota wars + 5 measurable migration triggers + Path A/B/C frameworks + cost forecasting worksheet + decision tree + 48-hour rollback checklist. Edition 1, ~40 pages, English. | $19. [Free preview Gist](https://gist.github.com/yurukusa/d66ffbe472df1231b59445f26fd25da9) |
| **[Safety Guide](https://zenn.dev/yurukusa/books/6076c23b1cb18b)** | End-to-end Claude Code safety setup. From first install to overnight autonomous runs. | ¥800 (~$5). Ch.3 free |
| **[CLAUDE.md Audit (service)](./SERVICES.md)** | Written audit of your CLAUDE.md + top-3 fixes, delivered within 48h via this repo's Issue tracker. | $29 (~¥3,980) |
| **[Token Burn Audit (service)](./SERVICES.md#2-token-burn-audit--29-3980)** | Diagnosis of your actual `/cost` output — top 3 waste patterns tied to Token Book Ch.8 symptoms, with per-pattern fixes. 48h delivery. | $29 (~¥3,980) |
| **[CC Safety Lab Founder](https://ko-fi.com/yurukusa)** | Monthly membership: 3–5 incident reports, 1 new hook (early access), 1 measured token-saving technique. | ¥500/month, grandfathered |

**Why pay?** A Max plan costs $200/month. One token waste incident burns 50–80% of your weekly quota in hours ([#46727](https://github.com/anthropics/claude-code/issues/46727)). One `rm -rf` incident costs days of recovery. The Token Book costs less than 2 hours of Max subscription time — and the CLAUDE.md templates alone can reduce consumption by 40%.

### v2.1.85: `if` Field Support

Hooks now support an `if` field for conditional execution. The hook process only spawns when the command matches the pattern — `ls` won't trigger a git-only hook.

```json
{
  "type": "command",
  "if": "Bash(git push *)",
  "command": "~/.claude/hooks/test-before-push.sh"
}
```

All example hooks include `if` field documentation in their headers.

## PermissionRequest Hooks (NEW)

Override Claude Code's built-in confirmation prompts. These run **after** the built-in safety checks, so they can auto-approve prompts that `permissions.allow` cannot suppress.

| Hook | What It Solves | Issue |
|------|---------------|-------|
| `quoted-flag-approver` | "Quoted characters in flag names" prompt on `git commit -m "msg"` | [#27957](https://github.com/anthropics/claude-code/issues/27957) |
| `bash-heuristic-approver` | Safety heuristic prompts for `$()`, backticks, ANSI-C quoting | [#30435](https://github.com/anthropics/claude-code/issues/30435) |
| `edit-always-allow` | Edit prompts in `.claude/skills/` despite `bypassPermissions` | [#36192](https://github.com/anthropics/claude-code/issues/36192) |
| `allow-git-hooks-dir` | Edit prompts in `.git/hooks/` for pre-commit/pre-push setup | |
| `allow-protected-dirs` | All protected directory prompts (CI/Docker environments) | [#36168](https://github.com/anthropics/claude-code/issues/36168) |
| `git-show-flag-sanitizer` | Strips invalid `--no-stat` from `git show` (wastes context on error) | [#13071](https://github.com/anthropics/claude-code/issues/13071) |
| `compact-blocker` | Blocks auto-compaction via PreCompact (preserves full context) | [#6689](https://github.com/anthropics/claude-code/issues/6689) |
| `webfetch-domain-allow` | Auto-approves WebFetch by domain (fixes broken `domain:*` wildcard) | [#9329](https://github.com/anthropics/claude-code/issues/9329) |

Install any of these: `npx cc-safe-setup --install-example <name>`

## Session Protection Hooks

Guards against issues that corrupt sessions or waste tokens silently.

| Hook | What It Solves | Issue |
|------|---------------|-------|
| `cch-cache-guard` | Blocks reads of Claude session/billing files that poison prompt cache via `cch=` substitution | [#40652](https://github.com/anthropics/claude-code/issues/40652) |
| `image-file-validator` | Blocks Read of fake image files (text in .png) that permanently corrupt sessions | [#24387](https://github.com/anthropics/claude-code/issues/24387) |
| `terminal-state-restore` | Restores Kitty keyboard protocol, cursor, bracketed paste on exit | [#39096](https://github.com/anthropics/claude-code/issues/39096) [#39272](https://github.com/anthropics/claude-code/issues/39272) |
| `large-read-guard` | Warns before reading large files via `cat`/`less` that waste context tokens | [#41617](https://github.com/anthropics/claude-code/issues/41617) |
| `prompt-usage-logger` | Logs every prompt with timestamps to track token consumption patterns | [#41249](https://github.com/anthropics/claude-code/issues/41249) |
| `compact-alert-notification` | Alerts when auto-compaction fires (tracks compact-rebuild cycles that burn tokens) | [#41788](https://github.com/anthropics/claude-code/issues/41788) |
| `token-budget-guard` | Blocks tool calls when estimated session cost exceeds a configurable threshold | [#38335](https://github.com/anthropics/claude-code/issues/38335) |
| `session-index-repair` | Rebuilds `sessions-index.json` on exit so `claude --resume` finds all sessions | [#25032](https://github.com/anthropics/claude-code/issues/25032) |
| `session-backup-on-start` | Backs up session JSONL files on start (protects against silent deletion) | [#41874](https://github.com/anthropics/claude-code/issues/41874) |
| `working-directory-fence` | Blocks Read/Edit/Write outside CWD (prevents operating on wrong project copy) | [#41850](https://github.com/anthropics/claude-code/issues/41850) |
| `mcp-warmup-wait` | Waits for MCP servers to initialize on session start (fixes first-turn tool errors) | [#41778](https://github.com/anthropics/claude-code/issues/41778) |
| `pre-compact-transcript-backup` | Full JSONL backup before compaction (protects against rate-limit data loss) | [#40352](https://github.com/anthropics/claude-code/issues/40352) |
| `conversation-history-guard` | Blocks access to session JSONL files (prevents 20x cache poisoning) | [#40524](https://github.com/anthropics/claude-code/issues/40524) |
| `read-before-edit` | Warns when Edit targets a file not recently Read (Read:Edit ratio dropped 70% — [#42796](https://github.com/anthropics/claude-code/issues/42796)) | [#42796](https://github.com/anthropics/claude-code/issues/42796) |
| `replace-all-guard` | Warns/blocks Edit `replace_all:true` (prevents bulk data corruption) | [#41681](https://github.com/anthropics/claude-code/issues/41681) |
| `ripgrep-permission-fix` | Auto-fixes vendored ripgrep +x permission on start (fixes broken commands/skills) | [#41933](https://github.com/anthropics/claude-code/issues/41933) |

## All 49 Commands

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
| `--install-example <name>` | Install from 711 examples |
| `--examples [filter]` | Browse examples by keyword |
| `--full` | All-in-one setup |
| `--status` | Check installed hooks |
| `--dry-run` | Preview changes |
| `--uninstall` | Remove all hooks |
| `--shield` | Maximum safety in one command |
| `--guard "rule"` | Instantly enforce a rule from English |
| `--suggest` | Predict risks from project analysis |
| `--from-claudemd` | Convert CLAUDE.md rules to hooks |
| `--team` | Project-level hooks for git sharing |
| `--profile [level]` | Switch safety profiles |
| `--save-profile <name>` | Save current hooks as profile |
| `--analyze` | Session analysis dashboard |
| `--health` | Hook health table |
| `--quickfix` | Auto-fix common problems |
| `--replay` | Visual blocked commands timeline |
| `--why <hook>` | Show real incident behind hook |
| `--migrate-from <tool>` | Migrate from other hook tools |
| `--diff-hooks [path]` | Compare hook configurations |
| `--init-project` | Full project setup (hooks + CLAUDE.md + CI) |
| `--score` | CI-friendly safety score (exit 1 if below threshold) |
| `--test-hook <name>` | Test a specific hook with sample input |
| `--simulate "cmd"` | Preview how all hooks react to a command |
| `--protect <path>` | Block edits to a file or directory |
| `--rules [file]` | Compile YAML rules into hooks |
| `--validate` | Validate all hook scripts (syntax + structure) |
| `--safe-mode` | Maximum protection: all safety hooks + strict config |
| `--changelog` | Show what changed in each version |
| `--report` | Generate safety report |
| `--help` | Show help |

## Quick Start by Scenario

| I want to... | Command |
|---|---|
| Make Claude Code safe right now | `npx cc-safe-setup --shield` |
| Stop permission prompt spam | `npx cc-safe-setup --install-example auto-approve-readonly` |
| Enforce a rule instantly | `npx cc-safe-setup --guard "never delete production data"` |
| See what risks my project has | `npx cc-safe-setup --suggest` |
| Convert CLAUDE.md rules to hooks | `npx cc-safe-setup --from-claudemd` |
| Share hooks with my team | `npx cc-safe-setup --team && git add .claude/` |
| Choose a safety level | `npx cc-safe-setup --profile strict` |
| See what Claude blocked today | `npx cc-safe-setup --replay` |
| Know why a hook exists | `npx cc-safe-setup --why destructive-guard` |
| Block silent memory file edits | `npx cc-safe-setup --install-example memory-write-guard` |
| Stop built-in skills editing opaquely | `npx cc-safe-setup --install-example skill-gate` |
| Diagnose why hooks aren't working | `npx cc-safe-setup --doctor` |
| Preview how hooks react to a command | `npx cc-safe-setup --simulate "git push origin main"` |
| Protect a specific file from edits | `npx cc-safe-setup --protect .env` |
| Stop .git/ write prompts | `npx cc-safe-setup --install-example allow-git-hooks-dir` |
| Auto-approve compound git commands | `npx cc-safe-setup --install-example auto-approve-compound-git` |
| Detect prompt injection patterns | `npx cc-safe-setup --install-example prompt-injection-detector` |
| Define rules in YAML, compile to hooks | `npx cc-safe-setup --rules rules.yaml` |
| Validate all hook scripts are correct | `npx cc-safe-setup --validate` |
| Maximum protection mode | `npx cc-safe-setup --safe-mode` |
| Migrate from Cursor/Windsurf | [Migration Guide](https://yurukusa.github.io/cc-safe-setup/migration-guide.html) |

## Plugin Marketplace

Install safety hooks as Claude Code plugins — no npm required:

```bash
/plugin marketplace add yurukusa/cc-safe-setup
/plugin install safety-essentials@cc-safe-setup
```

| Plugin | What it blocks |
|---|---|
| `safety-essentials` | rm -rf, force-push, hard-reset, .env overwrite, npm publish |
| `git-protection` | Force-push, main/master push, git clean, branch -D |
| `credential-guard` | .env write/edit, API keys in commands, service account files |

Also listed on [claudemarketplaces.com](https://claudemarketplaces.com).

## Common Pain Points (from GitHub Issues)

| Problem | Issue | Fix |
|---|---|---|
| Claude uses `cat`/`grep`/`sed` instead of built-in Read/Edit/Grep | [#19649](https://github.com/anthropics/claude-code/issues/19649) (48👍) | `npx cc-safe-setup --install-example prefer-builtin-tools` |
| `cd /path && cmd` bypasses permission allowlist | [#28240](https://github.com/anthropics/claude-code/issues/28240) (88👍) | `npx cc-safe-setup --install-example compound-command-approver` |
| Multiline commands skip pattern matching | [#11932](https://github.com/anthropics/claude-code/issues/11932) (47👍) | Use hooks instead of allowlist patterns for complex commands |
| No notification when Claude asks a question | [#13024](https://github.com/anthropics/claude-code/issues/13024) (52👍) | `npx cc-safe-setup --install-example notify-waiting` |
| `allow` overrides `ask` in permissions | [#6527](https://github.com/anthropics/claude-code/issues/6527) (17👍) | Use hooks to block dangerous commands instead of `ask` rules |
| Plans stored in `~/.claude/` with random names | [#12619](https://github.com/anthropics/claude-code/issues/12619) (163👍) | `npx cc-safe-setup --install-example plan-repo-sync` |

## How It Works

1. Writes hook scripts to `~/.claude/hooks/`
2. Updates `~/.claude/settings.json` to register the hooks
3. Restart Claude Code — hooks are active

Safe to run multiple times. Existing settings are preserved. A backup is created if settings.json can't be parsed.

**Maximum safety:** `npx cc-safe-setup --shield` — one command: fix environment, install hooks, detect stack, configure settings, generate CLAUDE.md.

**Instant rule:** `npx cc-safe-setup --guard "never touch the database"` — generates, installs, activates a hook instantly from plain English.

**Team setup:** `npx cc-safe-setup --team` — copy hooks to `.claude/hooks/` with relative paths, commit to repo for team sharing.

**Preview first:** `npx cc-safe-setup --dry-run`

**Check status:** `npx cc-safe-setup --status` — see which hooks are installed (exit code 1 if missing).

**Verify hooks work:** `npx cc-safe-setup --verify` — sends test inputs to each hook and confirms they block/allow correctly.

**Troubleshoot:** `npx cc-safe-setup --doctor` — diagnoses why hooks aren't working (jq, permissions, paths, shebang).

**Live monitor:** `npx cc-safe-setup --watch` — real-time dashboard of blocked commands during autonomous sessions.

**Uninstall:** `npx cc-safe-setup --uninstall` — removes all hooks and cleans settings.json.

**Requires:** [jq](https://jqlang.github.io/jq/) for JSON parsing (`brew install jq` / `apt install jq`).

**Note:** Hooks are skipped when Claude Code runs with `--bare` or `--dangerously-skip-permissions`. These modes bypass all safety hooks by design.

**Known limitations:**

- In headless mode (`-p` / `--print`), hook exit code 2 may not block tool execution ([#36071](https://github.com/anthropics/claude-code/issues/36071)). For CI pipelines, use interactive mode with hooks rather than `-p` mode.
- `FileChanged` notifications inject file contents into model context **before** hooks can intervene. If a sensitive file (`.env`, `credentials.json`) is modified externally during a session, its contents may appear in the conversation transcript regardless of hooks ([#44909](https://github.com/anthropics/claude-code/issues/44909)). Mitigation: use `dotenv-watch` to get alerted, and avoid editing sensitive files while Claude Code is running.

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

cc-safe-setup gives you 8 essential hooks. Want to know what else your setup needs?

Run `npx cc-health-check` (free, 20 checks) to see your current score. If it's below 80, the **[Claude Code Ops Kit](https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=github&utm_medium=readme&utm_campaign=safe-setup)** fills the gaps — 6 hooks + 5 templates + 9 scripts + install.sh. Pay What You Want ($0+).

**Starter Kit:** Want hooks + settings + templates in one download? The **[Claude Code Safety Kit](https://yurukusa.itch.io/claude-code-safety-kit)** bundles 5 safety hooks, a pre-configured settings.json, CLAUDE.md templates, and 800-hour operation tips. Name your price ($0+).

Or browse the free hooks: [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks)

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

- **claude-update-smart.sh** — Skip the 226 MB tarball download when already up-to-date (workaround for [#51243](https://github.com/anthropics/claude-code/issues/51243)). Turns 30 s checks into 0.3 s. Falls through to the real `claude update` when a new release exists or the registry is unreachable.
- **auto-approve-git-read.sh** — Auto-approve `git status`, `git log`, even with `-C` flags
- **auto-approve-ssh.sh** — Auto-approve safe SSH commands (`uptime`, `whoami`, etc.)
- **enforce-tests.sh** — Warn when source files change without corresponding test files
- **notify-waiting.sh** — Desktop notification when Claude Code waits for input (macOS/Linux/WSL2)
- **edit-guard.sh** — Block Edit/Write to protected files (defense-in-depth for [#37210](https://github.com/anthropics/claude-code/issues/37210))
- **auto-approve-build.sh** — Auto-approve npm/yarn/cargo/go/python build, test, and lint commands
- **auto-approve-docker.sh** — Auto-approve docker build, compose, ps, logs, and other safe commands
- **block-database-wipe.sh** — Block destructive database commands: Laravel `migrate:fresh`, Django `flush`, Rails `db:drop`, raw `DROP DATABASE` ([#46684](https://github.com/anthropics/claude-code/issues/46684) [#46650](https://github.com/anthropics/claude-code/issues/46650) [#37405](https://github.com/anthropics/claude-code/issues/37405) [#37439](https://github.com/anthropics/claude-code/issues/37439))
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

## Windows Support

Works on Windows via WSL or Git Bash. Native PowerShell is not supported (hooks are bash scripts).

**Common issue:** If you see `Permission denied` or `No such file` errors after install, run:

```bash
npx cc-safe-setup --doctor
```

This detects Windows backslash paths (`C:\Users\...` → `C:/Users/...`) and missing execute permissions.

See [Issue #1](https://github.com/yurukusa/cc-safe-setup/issues/1) for details.

## Troubleshooting

**[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — "Hook doesn't work" → step-by-step diagnosis. Covers every common failure pattern.

## settings.json Reference

**[SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)** — Complete reference for permissions, hooks, modes, and common configurations. Includes known limitations and workarounds.

## Migration Guide

**[MIGRATION.md](MIGRATION.md)** — Step-by-step guide for moving from permissions-only to permissions + hooks. Keep your existing config, add safety layers on top.

## Learn More

- **[Opus 4.7 Survival Guide](https://yurukusa.github.io/cc-safe-setup/opus-47-survival-guide.html)** — 61 known issues (76+ GitHub Issues + CVEs) with fixes: data loss, recursive spawn DoS, billing mismatch, subagent OOM, cache_read anomaly, allowedTools bypass, 1.7x token inflation, classifier failure, thinking summary bugs, 30-min stalls, enterprise hooks bypass, and more. [`npx cc-safe-setup --opus47`](#-opus-47-crisis-april-2026)
- **[Token Book (¥2,500)](https://zenn.dev/yurukusa/books/token-savings-guide)** — Cut token consumption in half. CLAUDE.md optimization, hook-based guards, context management, workflow design. 44,000 words with copy-paste templates. Intro + Ch.1 free. [Details](https://yurukusa.github.io/cc-safe-setup/token-book.html)
- **[Safety Guide (¥800)](https://zenn.dev/yurukusa/books/6076c23b1cb18b)** — Token consumption diagnosis, file loss prevention, autonomous operation safety. From 800+ hours of real incidents. [Chapter 3 free](https://zenn.dev/yurukusa/books/6076c23b1cb18b/viewer/3-code-quality)
- **[800 Hours Operation Record (¥800)](https://zenn.dev/yurukusa/books/3c3c3baee85f0a19)** — Non-engineer running Claude Code autonomously for 800 hours. Failures, recovery, revenue reality. [Chapter 2 free](https://zenn.dev/yurukusa/books/3c3c3baee85f0a19/viewer/2-first-failures)
- **[CC Safety Lab Founder (¥500/月, Ko-fi Membership)](https://ko-fi.com/yurukusa)** — Monthly companion to the Books. Each month delivers 3–5 curated incidents (with fixes), 1 new safety hook, 1 measured token-saving technique, and early access to Token Book updates. Founder price locked for charter members.
- **Wiki Guides**: [Token FAQ](https://github.com/yurukusa/cc-safe-setup/wiki/Claude-Code-Token-FAQ) · [CLAUDE.md Best Practices](https://github.com/yurukusa/cc-safe-setup/wiki/CLAUDE-md-Best-Practices) · [Token Optimization](https://github.com/yurukusa/cc-safe-setup/wiki/Token-Optimization-Guide)
- [Cookbook](COOKBOOK.md) — 26 practical recipes (block, approve, protect, monitor, diagnose)
- [Official Hooks Reference](https://code.claude.com/docs/en/hooks) — Claude Code hooks documentation
- [Hooks Cookbook](https://github.com/yurukusa/claude-code-hooks/blob/main/COOKBOOK.md) — 25 recipes from real GitHub Issues ([interactive version](https://yurukusa.github.io/claude-code-hooks/))
- [Skills Guide deep-dive (Qiita, 19K+ views)](https://qiita.com/yurukusa/items/f69920b4a02cf7e2988c) — Anthropic's official Skills PDF analyzed with 40% token reduction
- [Japanese guide (Qiita)](https://qiita.com/yurukusa/items/a9714b33f5d974e8f1e8) — この記事の日本語解説
- [Opus 4.7 breaking changes deep-dive (Hashnode)](https://yurukusa.hashnode.dev/opus-47-isnt-a-regression-but-your-46-prompts-are-now-broken) — Anthropic's 9 breaking changes, 5 workarounds, and the `task_budget` beta nobody mentions. Covers why `thinking-stall-detector` and `claude-md-reinjector` hooks exist
- [v2.1.85 `if` field guide (Qiita)](https://qiita.com/yurukusa/items/7079866e9dc239fcdd57) — Reduce hook overhead with conditional execution
- [Deny rules bypass vulnerability (Qiita)](https://qiita.com/yurukusa/items/f9c48bb44569bbf4492e) — 50+ subcommands disable all deny rules; hook-based defense
- [Hook Test Runner](https://github.com/yurukusa/cc-hook-test) — `npx cc-hook-test <hook.sh>` to auto-test any hook
- [Hook Registry](https://github.com/yurukusa/cc-hook-registry) — `npx cc-hook-registry search database` ([browse online](https://yurukusa.github.io/cc-hook-registry/))
- [Hooks Cheat Sheet](https://yurukusa.github.io/cc-safe-setup/cheatsheet.html) — printable A4 quick reference
- [Ecosystem Comparison](https://yurukusa.github.io/cc-safe-setup/ecosystem.html) — all Claude Code hook projects compared
- [The incident that inspired this tool](https://github.com/anthropics/claude-code/issues/36339) — NTFS junction rm -rf
- [How to prevent rm -rf disasters](https://yurukusa.github.io/cc-safe-setup/prevent-rm-rf.html) — real incidents and the hook that stops them
- [How to prevent force-push to main](https://yurukusa.github.io/cc-safe-setup/prevent-force-push.html) — branch protection via hooks
- [How to prevent secret leaks](https://yurukusa.github.io/cc-safe-setup/prevent-secret-leaks.html) — stop git add . from committing .env

### Free Gists

- [settings.json Complete Template](https://gist.github.com/yurukusa/8ec367cf65042bf9fbd83c35931e7ed1) — copy-paste ready safety configuration
- [First 3 Safety Steps](https://gist.github.com/yurukusa/72513272be9a4ee29b058e2b08453e1a) — 5-minute safety setup from scratch
- [CLAUDE.md Before/After](https://gist.github.com/yurukusa/f9d7df5930bfb6d36a25673e69720f7e) — 40% token reduction through better writing patterns
- [Token Savings Cheat Card](https://gist.github.com/yurukusa/cfe44bfbb3756eccaf51660466913a2d) — 5 techniques to cut consumption in half
- [Token Consumption Checklist](https://gist.github.com/yurukusa/db8700a9f9fa331d36664df2868274cb) — 10-item diagnostic
- [Outage Survival Kit](https://gist.github.com/yurukusa/a0e31171eecb527d0df1d5498bf5f5d0) — what to do when Claude Code is down
- [CLAUDE.md Token Optimizer](https://gist.github.com/yurukusa/2b98fd2e90c0c13f6918c9f915e08e27) — 35-line template, 40% token reduction (800h tested)
- [Worktree Safety Hooks](https://gist.github.com/yurukusa/98bd43c5d0d8a6ebbf2cf21bfc1e2907) — 3 hooks to protect against worktree deletion and cross-tree destruction
- [Opus 4.7 Emergency Checklist](https://gist.github.com/yurukusa/c95efaee4b670e067369ece08092960c) — token burn diagnosis + immediate fixes
- [Cache TTL Mitigation Guide](https://gist.github.com/yurukusa/178d3949cd2bd6fbfc275b408f9711d4) — #46829 cache TTL change (1h→5m) impact and 4 mitigations
- [Security Checkup Hooks](https://gist.github.com/yurukusa/81f79ae6d760b27c17f2cd642ea846d7) — 4 hooks for financial, PII, deny bypass, and background task protection
- [Cache Breakage Fix](https://gist.github.com/yurukusa/fe6ba0a6aee14207f27ecc84419878b4) — 2 root causes of prompt cache invalidation (#47107 git status, #47098 session restart)
- [CLAUDE.md Token Optimization Cheat Sheet](https://gist.github.com/yurukusa/556f67c493a2729ce9b1703f5003a227) — 5 CLAUDE.md patterns that reduce token consumption with before/after examples
- [Token Troubleshooting Guide](https://gist.github.com/yurukusa/47b8c3eadb77cf74946f450f992ddac2) — fix quota drain, cache bugs, 1M context trap. Symptom-based diagnosis with latest issue references
- [Token Optimization Guide (English)](https://gist.github.com/yurukusa/70ff830c0ad3dff83e53be26cd80bd0a) — 3 biggest token levers with hook code, practical walkthrough
- [Token Book Sampler: 5 Techniques](https://gist.github.com/yurukusa/4a867ba301b480f996c5b76e4b6a6fbc) — free preview of the Token Book — 5 immediate techniques to reduce consumption
- [Token Optimization Checklist](https://gist.github.com/yurukusa/4b75025beee916f9904f56b79eeb1217) — 10-step checklist to cut token consumption in half, with hook configs
- [3 Things That Actually Work](https://gist.github.com/yurukusa/621f6d1cc35816df3da2e07876b44e16) — CLAUDE.md sizing, cache TTL, subagent control — based on 800h data
- [Cache TTL Diagnostic](https://gist.github.com/yurukusa/3a5bdcfdd295bef17b3ee00978b299f2) — 3 patterns that break prompt cache + fixes
- [Token Book Ch.1 Free Preview](https://gist.github.com/yurukusa/de862573f18d1a0a68d411b696dbcb73) — Where are your Claude Code tokens going? The 4 layers of token consumption explained
- [Deny Rules Break After 50 Subcommands](https://gist.github.com/yurukusa/0463d240d7b725218289a556414c72a5) — the hook that fixes Claude Code's deny rule bypass vulnerability
- [Opus 4.7 Emergency Kit](https://gist.github.com/yurukusa/1970b20fed95a682b72eb6e857e61d30) — 5 commands to protect your data from Opus 4.7 regressions (auto mode broken, 23+ data loss incidents)
- [cache_read Billing Bug Guide](https://gist.github.com/yurukusa/d5dc731dbc69e3ca92d69832bed641cb) — Opus 4.7 cache_read billed at full rate. Anthropic confirmed. Max plan users losing quota 3-6x faster
- [Opus 4.7 Survival Guide Summary](https://gist.github.com/yurukusa/5d66f0bcfe3fbfc73e6db106e10c533d) — 50 known issues with quick reference table, free diagnostic tools, and one-command fix
- [Opus 4.7 Known Issues Quick Reference](https://gist.github.com/yurukusa/2c1effab34a7554130d2704fdac59dff) — 26 issues / 43+ GitHub bugs in one table. Severity ratings and direct issue links
- [4 New Critical Issues (April 18)](https://gist.github.com/yurukusa/37c19b5b7f50fd8bbbeda5e1336c352e) — DoS via recursive spawn, subagent OOM, billing mismatch, UI/CLI model mismatch
- [トークン消費を半分にする方法](https://gist.github.com/yurukusa/bf4040a905148d9ca02898a53185fae1) — 800時間の実測データ＋設定テンプレート（日本語）
- [How to Cut Token Usage in Half](https://gist.github.com/yurukusa/704d5cf9874f553dad5c46fccf53b09f) — 800h real data + config templates (English)
- [Compaction Triple Threat](https://gist.github.com/yurukusa/aa15f2065199c6fac4dcd3796fbaf90f) — 3 compaction bugs active simultaneously (#50402 + #50467 + #50492)
- [Sandbox Relative Path Bug (CRITICAL)](https://gist.github.com/yurukusa/a98efb6c561f92c82bcd49125af3b32a) — denyWrite/denyRead silently ignores relative paths (#50454)
- [27 Token Symptoms Quick Reference](https://gist.github.com/yurukusa/03a379854fa0f8eca091a75f7aab593b) — all 27 known token failure modes with top 5 killers table and April 2026 new symptoms
- [Token Saving Checklist (15 Items)](https://gist.github.com/yurukusa/6bd0d0a38a4887fc36475dd1f765ecd1) — ordered by impact: critical (30-50%), important (10-20%), good practice (5-10%)
- [Opus 4.7 Survival Cheatsheet](https://gist.github.com/yurukusa/f2d6e261338eeda70f0ed9507f995c13) — 46 known problems, quick fixes under 60 seconds, full reference table

### Professional Services

Need help configuring Claude Code safely? [**Safety Setup Service**](https://yurukusa.github.io/cc-safe-setup/services.html) — audit, token optimization, and custom hooks by the cc-safe-setup team.

## FAQ

**Q: I installed hooks but Claude says "Unknown skill: claude-code-hooks:setup"**

cc-safe-setup installs **hooks**, not skills or plugins. Hooks run automatically in the background — you don't invoke them manually. After install + restart, try running a dangerous command; the hook will block it silently.

**Q: `cc-health-check` says to run `cc-safe-setup` but I already did**

cc-safe-setup covers Safety Guards (75-100%) and Monitoring (context-monitor). The other health check dimensions (Code Quality, Recovery, Coordination) require additional CLAUDE.md configuration or manual hook installation from [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks).

**Q: Will hooks slow down Claude Code?**

No. Each hook runs in ~10ms. They only fire on specific events (before tool use, after edits, on stop). No polling, no background processes.

**Q: My permission patterns don't match compound commands like `cd /path && git status`**

This is a known limitation of Claude Code's permission system ([#16561](https://github.com/anthropics/claude-code/issues/16561), [#28240](https://github.com/anthropics/claude-code/issues/28240)). Permission matching evaluates only the first token (`cd`), not the actual command (`git status`). Use a PreToolUse hook instead — hooks see the full command string and can parse compound commands. See `compound-command-allow.sh` in examples.

**Q: `--dangerously-skip-permissions` still prompts for `.claude/` and `.git/` writes**

Since v2.1.78, protected directories always prompt regardless of permission mode ([#35668](https://github.com/anthropics/claude-code/issues/35668)). Use a PermissionRequest hook to auto-approve specific protected directory operations. See `allow-protected-dirs.sh` in examples.

**Q: `allow: ["Bash(*)"]` overrides my `ask` rules**

`allow` takes precedence over `ask`. If you allow all Bash, ask rules are ignored ([#6527](https://github.com/anthropics/claude-code/issues/6527)). Use PreToolUse hooks to block dangerous commands instead of relying on the ask/allow priority system.

**Q: Hooks silently fail on macOS (Homebrew `jq` not found)**

Claude Code runs hooks with a restricted PATH that excludes `/opt/homebrew/bin` ([#46954](https://github.com/anthropics/claude-code/issues/46954)). If `jq` is installed via Homebrew, hooks silently exit 0. Fix: add `export PATH="/opt/homebrew/bin:$PATH"` at the top of your hook script, or use absolute paths like `/opt/homebrew/bin/jq`. Inline hooks in `settings.json` may also be affected — add a PATH export prefix: `export PATH="/opt/homebrew/bin:$PATH"; INPUT=$(cat); ...`

**Q: How is this different from [claude-token-efficient](https://github.com/drona23/claude-token-efficient)?**

Different goals. claude-token-efficient optimizes CLAUDE.md to make Claude's responses shorter and cheaper. cc-safe-setup prevents dangerous operations (file deletion, credential leaks, force-push). They work well together: use claude-token-efficient for cost reduction, cc-safe-setup for safety. For comprehensive token optimization beyond CLAUDE.md (hooks, context management, workflow design), see the [Token Book](https://yurukusa.github.io/cc-safe-setup/token-book.html).

**Still stuck?** See the full [Permission Troubleshooting Flowchart](https://gist.github.com/yurukusa/b64217ffcb908fa309dbfcfa368cd84d) for step-by-step diagnosis.

## Contributing

**Report a problem:** Found a false positive or a bypass? Open an [issue](https://github.com/yurukusa/cc-safe-setup/issues/new). Include the command that was incorrectly blocked/allowed and your OS.

**Request a hook:** Describe the problem you're trying to prevent (not the solution). We'll figure out the hook together.

**Write a hook:** Fork, add your `.sh` file to `examples/`, add tests to `test.sh`, and open a PR. Every hook needs:
- A comment header explaining what it blocks and why
- At least 7 test cases (block, allow, empty input, edge cases)
- `bash -n` syntax validation passing

**Share your experience:** Used cc-safe-setup and have feedback? Open a discussion or comment on any issue. We read everything.

If cc-safe-setup saved you from a disaster (or just saved you time), a ⭐ helps others find it too.

## Affiliate Program

If you write or teach about Claude Code, you can earn 30% commission promoting our paid books and kits. Apply with any Gumroad account — no application form, 30-day cookie window, automatic Gumroad payouts:

- [yurukusa.gumroad.com/affiliates](https://yurukusa.gumroad.com/affiliates)

Eligible products include the [Migration Playbook](https://yurukusa.gumroad.com/l/claude-code-migration-playbook) ($19), [Token Book EN](https://yurukusa.gumroad.com/l/azrdt) ($12), [Complete Survival Kit](https://yurukusa.gumroad.com/l/poqhoo), [CLAUDE.md Templates](https://yurukusa.gumroad.com/l/iaple), and three other Claude Code titles.

## Also by yurukusa

- [quiet life](https://yurukusa.github.io/quiet-life/) — Touch the dark. Something alive appears
- [deep breath](https://yurukusa.github.io/deep-breath/) — Breathe with the light
- [star moss](https://yurukusa.github.io/star-moss/) — Drag to grow

## License

MIT
