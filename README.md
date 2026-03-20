# cc-safe-setup

[![npm version](https://img.shields.io/npm/v/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)
[![npm downloads](https://img.shields.io/npm/dw/cc-safe-setup)](https://www.npmjs.com/package/cc-safe-setup)

**One command to make Claude Code safe for autonomous operation.**

```bash
npx cc-safe-setup
```

Installs 4 production-tested safety hooks in ~10 seconds. Zero dependencies. No manual configuration.

```
  cc-safe-setup
  Make Claude Code safe for autonomous operation

  Prevents real incidents:
  ✗ rm -rf deleting entire user directories (NTFS junction traversal)
  ✗ Untested code pushed to main at 3am
  ✗ Syntax errors cascading through 30+ files
  ✗ Sessions losing all context with no warning

  Hooks to install:

  ● Destructive Command Blocker
  ● Branch Push Protector
  ● Post-Edit Syntax Validator
  ● Context Window Monitor
  ● Bash Comment Stripper
  ● cd+git Auto-Approver

  Install all 6 safety hooks? [Y/n] Y

  ✓ Destructive Command Blocker
  ✓ Branch Push Protector
  ✓ Post-Edit Syntax Validator
  ✓ Context Window Monitor
  ✓ Bash Comment Stripper
  ✓ cd+git Auto-Approver
  ✓ settings.json updated

  Done. 6 safety hooks installed.
```

## Why This Exists

A Claude Code user [lost their entire C:\Users directory](https://github.com/anthropics/claude-code/issues/36339) when `rm -rf` followed NTFS junctions. Another had untested code pushed to main at 3am. Syntax errors cascaded through 30+ files before anyone noticed.

Claude Code ships with no safety hooks by default. This tool fixes that.

## What Gets Installed

| Hook | Prevents | Trigger |
|------|----------|---------|
| **Destructive Guard** | `rm -rf /`, `git reset --hard`, `git clean -fd` | PreToolUse (Bash) |
| **Branch Guard** | Direct pushes to main/master | PreToolUse (Bash) |
| **Syntax Check** | Python, Shell, JSON, YAML, JS errors after edits | PostToolUse (Edit\|Write) |
| **Context Monitor** | Session state loss from context window overflow | PostToolUse |
| **Comment Stripper** | Bash comments breaking permission allowlists ([#29582](https://github.com/anthropics/claude-code/issues/29582)) | PreToolUse (Bash) |
| **cd+git Auto-Approver** | Permission prompt spam for `cd /path && git log` ([#32985](https://github.com/anthropics/claude-code/issues/32985)) | PreToolUse (Bash) |

Each hook exists because a real incident happened without it.

## How It Works

1. Writes hook scripts to `~/.claude/hooks/`
2. Updates `~/.claude/settings.json` to register the hooks
3. Restart Claude Code — hooks are active

Safe to run multiple times. Existing settings are preserved. A backup is created if settings.json can't be parsed.

**Preview first:** `npx cc-safe-setup --dry-run`

**Uninstall:** `npx cc-safe-setup --uninstall` — removes all 4 hooks and cleans settings.json.

**Requires:** [jq](https://jqlang.github.io/jq/) for JSON parsing (`brew install jq` / `apt install jq`).

## After Installing

Verify your setup:

```bash
npx cc-health-check
```

## Full Kit

cc-safe-setup gives you 4 essential hooks. For the complete autonomous operation toolkit:

**[Claude Code Ops Kit](https://yurukusa.github.io/cc-ops-kit-landing/?utm_source=github&utm_medium=readme&utm_campaign=safe-setup)** ($19) — 11 hooks + 6 templates + 3 exclusive tools + install.sh. Production-ready in 15 minutes.

Or start with the free hooks: [claude-code-hooks](https://github.com/yurukusa/claude-code-hooks)

## Related

- [Japanese guide (Qiita)](https://qiita.com/yurukusa/items/a9714b33f5d974e8f1e8) — この記事の日本語解説
- [The incident that inspired this tool](https://github.com/anthropics/claude-code/issues/36339) — NTFS junction rm -rf

## License

MIT
